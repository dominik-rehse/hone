# hone: judge the table rewrites in one migration file. land_rewrites in
# scripts/worktree.sh feeds this and reads its verdicts.
#
# A table rewrite is: CREATE TABLE new, INSERT INTO new SELECT * FROM old,
# DROP TABLE old, ALTER TABLE new RENAME TO old. SQLite needs it to drop or
# change most columns. The DROP reads as destructive SQL, yet the rewrite
# loses no data when the copy keeps every row and every column.
#
# The copy must be SELECT * with no column list on either side. The old
# columns come from the migrations, and the live table can hold one that no
# migration shows. A copy that names its columns drops it without an error.
# With *, a live table whose columns differ makes the copy fail loudly.
#
# The verdict is "lossless" only when the text proves it. Anything this does
# not understand is a "no" with its reason, and the authority gate fires as
# for any other destructive statement. A wrong "ok" lands data loss
# unattended, so every doubt resolves to "no".
#
# Input: file sections, each opened by a line "\001<role>\t<path>". Roles:
#   schema  the schema file at the merge base, replayed first
#   prior   an earlier migration of the same set, in run order
#   opaque  a reason the earlier migrations cannot be replayed
#   target  the added migration file under judgment, last
# Output, one line per rewritten table of the target:
#   ok<TAB><table><TAB><line of its DROP><TAB><what was proven>
#   no<TAB><table><TAB>0<TAB><the first fact that could not be shown>
# Names come out lower-cased. SQL compares them without case.

BEGIN { nf = 0; ns = 0; opaque = "" }

# ---- tokenizer ------------------------------------------------------------

substr($0, 1, 1) == "\001" {
    finish_stmt()
    nf++
    split(substr($0, 2), hdr, "\t")
    frole[nf] = hdr[1]; fpath[nf] = hdr[2]; lineno = 0
    if (hdr[1] == "opaque" && opaque == "") opaque = hdr[2]
    incomment = 0; instr = ""
    next
}

{
    lineno++
    if (frole[nf] == "opaque") next
    low = tolower($0)
    # A down or rollback section would replay backwards. Its marker is a
    # comment, so it is read here, before the tokenizer strips comments.
    if (low ~ /^[ \t]*--/ && low ~ /(^|[^a-z])(down|rollback|revert|undo)([^a-z]|$)/)
        downmark[nf] = 1
    tokenize_line($0)
}

END {
    finish_stmt()
    judge()
}

function add_tok(type, text) {
    if (!(ns in sn)) start_stmt()
    sn[ns]++
    TT[ns, sn[ns]] = type
    T[ns, sn[ns]] = text
    send[ns] = lineno
    if (!((nf, lineno) in lastst) || lastst[nf, lineno] != ns) {
        lastst[nf, lineno] = ns
        lstmts[nf, lineno] = lstmts[nf, lineno] " " ns
    }
}

function start_stmt() {
    sn[ns] = 0; sfile[ns] = nf; sstart[ns] = lineno
    trig = 0; inbody = 0; casedepth = 0
}

# Close the open statement, if it has tokens, and open the next.
function finish_stmt() {
    if ((ns in sn) && sn[ns] > 0) ns++
    else delete sn[ns]
}

function tokenize_line(s,    c, n, q, j) {
    while (s != "") {
        if (incomment) {
            j = index(s, "*/")
            if (j == 0) return
            s = substr(s, j + 2); incomment = 0; continue
        }
        if (instr != "") {
            q = (instr == "[") ? "]" : instr
            j = index(s, q)
            if (j == 0) { buf = buf substr(s, 1) "\n"; return }
            # A doubled quote is an escaped quote, not the end.
            if (q != "]" && substr(s, j + 1, 1) == q) {
                buf = buf substr(s, 1, j); s = substr(s, j + 2); continue
            }
            buf = buf substr(s, 1, j - 1); s = substr(s, j + 1)
            if (instr == "'") add_tok("S", buf)
            else add_tok("Q", toupper(buf))
            instr = ""; continue
        }
        c = substr(s, 1, 1)
        if (c ~ /[ \t\r]/) { s = substr(s, 2); continue }
        if (substr(s, 1, 2) == "--") return
        if (substr(s, 1, 2) == "/*") { s = substr(s, 3); incomment = 1; continue }
        if (c == "'" || c == "\"" || c == "`" || c == "[") {
            instr = c; buf = ""; s = substr(s, 2); continue
        }
        if (match(s, /^[A-Za-z_][A-Za-z0-9_$]*/)) {
            word(toupper(substr(s, 1, RLENGTH))); s = substr(s, RLENGTH + 1); continue
        }
        if (match(s, /^[0-9][0-9A-Za-z_.]*/)) {
            add_tok("N", substr(s, 1, RLENGTH)); s = substr(s, RLENGTH + 1); continue
        }
        s = substr(s, 2)
        if (c == ";") {
            if (!(ns in sn)) continue
            # Inside a trigger body a ";" ends a body statement, not the
            # trigger. Reading the body as top-level statements would take a
            # trigger's INSERT for the copy.
            if (inbody) { add_tok("P", c); continue }
            finish_stmt(); continue
        }
        add_tok("P", c)
    }
}

function word(w) {
    add_tok("W", w)
    if (sn[ns] <= 3 && w == "TRIGGER" && T[ns, 1] == "CREATE") trig = 1
    if (!trig) return
    if (w == "BEGIN" && !inbody) { inbody = 1; return }
    if (!inbody) return
    if (w == "CASE") casedepth++
    else if (w == "END") { if (casedepth > 0) casedepth--; else inbody = 0 }
}

# ---- parse helpers ----------------------------------------------------------

function kw(k, i, w) { return TT[k, i] == "W" && T[k, i] == w }
function isname(k, i) { return TT[k, i] == "W" || TT[k, i] == "Q" }

# Read a possibly schema-qualified name at token i. Sets NAME and returns the
# index after it, or 0 when no name is there.
function getname(k, i) {
    if (!isname(k, i)) return 0
    if (T[k, i + 1] == "." && TT[k, i + 1] == "P" && isname(k, i + 2)) {
        NAME = T[k, i + 2]; return i + 3
    }
    NAME = T[k, i]; return i + 1
}

# SQLite's type affinity rules, from the declared type text.
function affinity(t) {
    if (t ~ /INT/) return "INTEGER"
    if (t ~ /CHAR|CLOB|TEXT/) return "TEXT"
    if (t == "" || t ~ /BLOB/) return "BLOB"
    if (t ~ /REAL|FLOA|DOUB/) return "REAL"
    return "NUMERIC"
}

function colstop(w) {
    return w == "CONSTRAINT" || w == "PRIMARY" || w == "NOT" || w == "NULL" \
        || w == "UNIQUE" || w == "CHECK" || w == "DEFAULT" || w == "COLLATE" \
        || w == "REFERENCES" || w == "GENERATED" || w == "AS"
}

# Parse one column definition from token a to b. Sets DNAME, DAFF, DGEN and
# DCONFLICT. Returns 0 when the tokens are not a column definition.
function coldef(k, a, b,    i, t, d) {
    if (a > b || !isname(k, a)) return 0
    DNAME = T[k, a]; DGEN = 0; DCONFLICT = 0; t = ""; d = 0
    for (i = a + 1; i <= b; i++) {
        if (T[k, i] == "(" && TT[k, i] == "P") d++
        else if (T[k, i] == ")" && TT[k, i] == "P") d--
        else if (d == 0 && TT[k, i] == "W" && colstop(T[k, i])) break
        else if (d == 0 && TT[k, i] == "P") return 0
        else if (d == 0) t = t " " T[k, i]
    }
    for (; i <= b; i++) {
        if (kw(k, i, "GENERATED") || kw(k, i, "AS")) DGEN = 1
        if (kw(k, i, "ON") && kw(k, i + 1, "CONFLICT")) DCONFLICT = 1
    }
    DAFF = affinity(t)
    return 1
}

# Parse CREATE TABLE. Sets CNAME, CN, CCOL[j], CAFF[j], CGEN, CCONFLICT,
# CIFNX, and returns 1 when the column list was read, 0 when the statement
# creates table CNAME in a way this cannot read, -1 when it is no CREATE TABLE.
function parse_create(k,    i, a, d, isc) {
    CNAME = ""; CN = 0; CGEN = 0; CCONFLICT = 0; CIFNX = 0
    if (!kw(k, 1, "CREATE")) return -1
    i = 2
    if (kw(k, i, "TEMP") || kw(k, i, "TEMPORARY")) i++
    if (kw(k, i, "VIRTUAL") && kw(k, i + 1, "TABLE")) {
        i += 2
        if (kw(k, i, "IF")) i += 3
        if (!getname(k, i)) return -1
        CNAME = NAME; return 0
    }
    if (!kw(k, i, "TABLE")) return -1
    i++
    if (kw(k, i, "IF") && kw(k, i + 1, "NOT") && kw(k, i + 2, "EXISTS")) { CIFNX = 1; i += 3 }
    i = getname(k, i)
    if (!i) return -1
    CNAME = NAME
    if (T[k, i] != "(" || TT[k, i] != "P") return 0
    d = 1; a = i + 1
    for (i = i + 1; i <= sn[k]; i++) {
        if (TT[k, i] != "P") continue
        if (T[k, i] == "(") d++
        else if (T[k, i] == ")") d--
        if (d == 1 && T[k, i] == "," || d == 0) {
            if (!table_part(k, a, i - 1)) return 0
            a = i + 1
            if (d == 0) break
        }
    }
    if (d != 0 || CN == 0) return 0
    for (i = i + 1; i <= sn[k]; i++) if (kw(k, i, "AS")) return 0
    return 1
}

function table_part(k, a, b,    w, i) {
    w = (TT[k, a] == "W") ? T[k, a] : ""
    if (w == "CONSTRAINT" || w == "PRIMARY" || w == "UNIQUE" || w == "CHECK" || w == "FOREIGN") {
        for (i = a; i < b; i++) if (kw(k, i, "ON") && kw(k, i + 1, "CONFLICT")) CCONFLICT = 1
        return 1
    }
    if (!coldef(k, a, b)) return 0
    CN++; CCOL[CN] = DNAME; CAFF[CN] = DAFF
    if (DGEN) CGEN = 1
    if (DCONFLICT) CCONFLICT = 1
    return 1
}

# ---- replay: table -> columns ------------------------------------------------

function forget(t,    j) {
    for (j = 1; j <= ncol[t]; j++) { delete col[t, j]; delete aff[t, j] }
    delete ncol[t]; delete known[t]
}

function unknown(t, why) { forget(t); known[t] = 0; why_unknown[t] = why }

function set_from_create(t,    j) {
    forget(t); known[t] = 1; ncol[t] = CN
    for (j = 1; j <= CN; j++) { col[t, j] = CCOL[j]; aff[t, j] = CAFF[j] }
    if (CGEN) unknown(t, "it has a generated column")
}

function colidx(t, c,    j) {
    for (j = 1; j <= ncol[t]; j++) if (col[t, j] == c) return j
    return 0
}

function where(k) { return fpath[sfile[k]] ":" sstart[k] }

# Mark every known table this statement names as unknown.
function taint(k, why,    i) {
    for (i = 1; i <= sn[k]; i++)
        if (isname(k, i) && (T[k, i] in known)) unknown(T[k, i], why)
}

function replay(k,    r, t, i, j, c, n, why) {
    why = "land cannot read " where(k)
    if (kw(k, 1, "CREATE")) {
        r = parse_create(k)
        if (r < 0) {
            # CREATE INDEX, VIEW or TRIGGER leaves the columns alone.
            if (!kw(k, 2, "TABLE") && !kw(k, 3, "TABLE")) return
            taint(k, why); return
        }
        t = CNAME
        if (r == 0) { unknown(t, why); return }
        if (t in known) {
            if (!CIFNX || !known[t] || !same_as_create(t)) unknown(t, "two definitions disagree at " where(k))
            return
        }
        set_from_create(t); return
    }
    if (kw(k, 1, "DROP") && kw(k, 2, "TABLE")) {
        i = 3
        if (kw(k, i, "IF") && kw(k, i + 1, "EXISTS")) i += 2
        i = getname(k, i)
        if (!i) { taint(k, why); return }
        forget(NAME)
        if (i <= sn[k]) taint(k, why)
        return
    }
    if (kw(k, 1, "ALTER") && kw(k, 2, "TABLE")) {
        i = 3
        if (kw(k, i, "IF") && kw(k, i + 1, "EXISTS")) i += 2
        i = getname(k, i)
        if (!i) { taint(k, why); return }
        t = NAME
        if (!(t in known) || !known[t]) { taint(k, why); unknown(t, why); return }
        if (kw(k, i, "ADD")) {
            i++
            if (kw(k, i, "COLUMN")) i++
            for (j = i; j <= sn[k]; j++) if (T[k, j] == "," && TT[k, j] == "P") { unknown(t, why); return }
            if (!coldef(k, i, sn[k]) || DGEN || colidx(t, DNAME)) { unknown(t, why); return }
            n = ++ncol[t]; col[t, n] = DNAME; aff[t, n] = DAFF
            return
        }
        if (kw(k, i, "DROP")) {
            i++
            if (kw(k, i, "COLUMN")) i++
            c = colidx(t, T[k, i])
            if (!isname(k, i) || !c || i != sn[k]) { unknown(t, why); return }
            for (j = c; j < ncol[t]; j++) { col[t, j] = col[t, j + 1]; aff[t, j] = aff[t, j + 1] }
            delete col[t, ncol[t]]; delete aff[t, ncol[t]]; ncol[t]--
            return
        }
        if (kw(k, i, "RENAME") && kw(k, i + 1, "TO")) {
            j = getname(k, i + 2)
            if (!j || j <= sn[k] || (NAME in known)) { taint(k, why); unknown(t, why); return }
            n = ncol[t]; known[NAME] = 1; ncol[NAME] = n
            for (j = 1; j <= n; j++) { col[NAME, j] = col[t, j]; aff[NAME, j] = aff[t, j] }
            forget(t); return
        }
        if (kw(k, i, "RENAME")) {
            i++
            if (kw(k, i, "COLUMN")) i++
            c = colidx(t, T[k, i])
            if (!c || !kw(k, i + 1, "TO") || !isname(k, i + 2) || i + 2 != sn[k] \
                || colidx(t, T[k, i + 2])) { unknown(t, why); return }
            col[t, c] = T[k, i + 2]; return
        }
        unknown(t, why); return
    }
    # Any other verb that can reshape a table (RENAME TABLE, a vendor ALTER)
    # makes every table it names unknown.
    if (kw(k, 1, "ALTER") || kw(k, 1, "RENAME")) taint(k, why)
}

function same_as_create(t,    j) {
    if (ncol[t] != CN) return 0
    for (j = 1; j <= CN; j++) if (col[t, j] != CCOL[j] || aff[t, j] != CAFF[j]) return 0
    return 1
}

# ---- judgment -----------------------------------------------------------------

# The table an INSERT, REPLACE, UPDATE or DELETE writes to, or "".
function write_target(k,    i) {
    i = 0
    if (kw(k, 1, "INSERT") || kw(k, 1, "REPLACE")) {
        for (i = 2; i <= 4; i++) if (kw(k, i, "INTO")) break
        if (i > 4) return ""
        i++
    } else if (kw(k, 1, "UPDATE")) {
        i = 2
        if (kw(k, i, "OR")) i += 2
    } else if (kw(k, 1, "DELETE") && kw(k, 2, "FROM")) i = 3
    else return ""
    return getname(k, i) ? NAME : ""
}

function dropped(k,    i) {
    if (!kw(k, 1, "DROP") || !kw(k, 2, "TABLE")) return ""
    i = 3
    if (kw(k, i, "IF") && kw(k, i + 1, "EXISTS")) i += 2
    i = getname(k, i)
    return (i && i > sn[k]) ? NAME : ""
}

# The table an ALTER TABLE x RENAME TO y renames to y, if the statement is that.
function renamed_to(k, y,    i) {
    if (!kw(k, 1, "ALTER") || !kw(k, 2, "TABLE")) return ""
    i = getname(k, 3)
    if (!i || !kw(k, i, "RENAME") || !kw(k, i + 1, "TO")) return ""
    src = NAME
    i = getname(k, i + 2)
    return (i && i > sn[k] && NAME == y) ? src : ""
}

function judge(    k, t, first, last, tlist, n, i, verdict) {
    first = -1
    for (k = 0; k < ns; k++) if (frole[sfile[k]] == "target") { if (first < 0) first = k; last = k }
    if (first < 0) return
    tf = sfile[first]
    n = 0
    for (k = first; k <= last; k++) {
        t = dropped(k)
        if (t != "" && !(t in seen)) { seen[t] = 1; tlist[++n] = t }
    }
    for (i = 1; i <= n; i++) {
        t = tlist[i]
        if (!is_rewrite(t, first, last)) continue
        verdict = check(t, first, last)
        if (verdict ~ /^ok\t/) print verdict
        else printf "no\t%s\t0\t%s\n", tolower(t), verdict
    }
}

function is_rewrite(t, first, last,    k, i) {
    for (k = first; k <= last; k++) {
        if (renamed_to(k, t) != "") return 1
        if (write_target(k) == "") continue
        for (i = 1; i < sn[k]; i++) if (kw(k, i, "FROM") && getname(k, i + 1) && NAME == t) return 1
    }
    return 0
}

function check(t, first, last,    k, kd, kr, kc, kcr, nd, nr, nc, ncr, nw, i, j, a, nt, star, named, lst, cols, fk) {
    delete ncol_new; delete naff_new
    delete known; delete ncol; delete col; delete aff; delete why_unknown
    if (opaque != "") return "the earlier migrations cannot be replayed: " opaque
    if (downmark[tf]) return "the file has a down or rollback section"
    for (k = 0; k < first; k++) if (downmark[sfile[k]]) return "an earlier migration has a down or rollback section: " fpath[sfile[k]]

    nd = 0; nr = 0
    for (k = first; k <= last; k++) {
        if (dropped(k) == t) { nd++; kd = k }
        if ((a = renamed_to(k, t)) != "") { nr++; kr = k; newt = a }
    }
    if (nd != 1) return "it drops " tolower(t) " more than once"
    if (nr != 1) return "no single ALTER TABLE ... RENAME TO " tolower(t)
    if (kr < kd) return "the rename to " tolower(t) " comes before its drop"

    nc = 0; ncr = 0; nw = 0
    for (k = first; k <= last; k++) {
        a = write_target(k)
        if (a == newt || a == t) {
            if (a == newt && kw(k, 1, "INSERT") && k < kd) { nc++; kc = k } else nw++
        }
        if (kw(k, 1, "CREATE") && parse_create(k) >= 0 && CNAME == newt) { ncr++; kcr = k }
        if (kw(k, 1, "CREATE") && k < kr && (kw(k, 2, "TRIGGER") || kw(k, 3, "TRIGGER")))
            for (i = 1; i <= sn[k]; i++) if (isname(k, i) && (T[k, i] == t || T[k, i] == newt))
                return "a trigger on " tolower(T[k, i]) " exists during the copy"
    }
    if (nw) return "another statement writes to " tolower(t) " or " tolower(newt)
    if (nc != 1) return "no single INSERT INTO " tolower(newt) " before the drop"
    if (ncr != 1 || kcr > kc) return "no single CREATE TABLE " tolower(newt) " before the copy"
    if (parse_create(kcr) != 1) return "land cannot read CREATE TABLE " tolower(newt)
    if (CGEN) return tolower(newt) " has a generated column"
    if (CCONFLICT) return tolower(newt) " has an ON CONFLICT clause, which can drop rows"
    nt = CN
    for (j = 1; j <= CN; j++) { ncol_new[j] = CCOL[j]; naff_new[CCOL[j]] = CAFF[j] }

    # The copy: INSERT INTO new SELECT [ALL] * FROM old, and nothing after
    # old. A column list on either side is read far enough to name the
    # reason, then refused.
    k = kc
    if (!kw(k, 2, "INTO")) return "the copy is not a plain INSERT INTO (" T[k, 2] ")"
    i = getname(k, 3)
    named = 0
    if (T[k, i] == "(" && TT[k, i] == "P") {
        named = 1
        for (i++; i <= sn[k] && T[k, i] != ")"; i++) {
            if (T[k, i] == "," && TT[k, i] == "P") continue
            if (!isname(k, i)) return "land cannot read the column list of the copy"
        }
        i++
    }
    if (!kw(k, i, "SELECT")) return "the copy is not INSERT ... SELECT"
    i++
    if (kw(k, i, "DISTINCT")) return "the copy selects DISTINCT rows"
    if (kw(k, i, "ALL")) i++
    star = 0
    for (;;) {
        if (T[k, i] == "*" && TT[k, i] == "P") { star++; i++ }
        else {
            if (isname(k, i) && T[k, i + 1] == "." && isname(k, i + 2)) {
                if (T[k, i] != t) return "the copy reads a column of another table"
                i += 2
            }
            if (!isname(k, i)) return "the copy computes a value instead of reading a column"
            named = 1; i++
        }
        if (T[k, i] == "," && TT[k, i] == "P") { i++; continue }
        break
    }
    if (!kw(k, i, "FROM")) return "the copy computes a value instead of reading a column"
    i = getname(k, i + 1)
    if (!i) return "land cannot read the source of the copy"
    if (NAME != t) return "the copy reads from " tolower(NAME) ", not " tolower(t)
    if (i <= sn[k]) return "the copy filters or joins rows (" T[k, i] " after FROM " tolower(t) ")"
    if (named) return "the copy names its columns, so a column that no migration shows would be lost"
    if (star != 1) return "the copy selects * more than once"

    # The old columns, replayed up to the copy. * copies by position, so
    # each position must hold the same column with the same affinity.
    for (a = 0; a < kc; a++) replay(a)
    if (!(t in known)) return "no earlier migration or schema file defines " tolower(t)
    if (!known[t]) return "the columns of " tolower(t) " are unknown: " why_unknown[t]
    if (nt != ncol[t]) return "the copy uses * and " tolower(newt) " has " nt " columns, " tolower(t) " has " ncol[t]
    for (j = 1; j <= nt; j++) {
        if (ncol_new[j] != col[t, j]) return "the copy uses * and column " j " is " tolower(col[t, j]) " in " tolower(t) ", " tolower(ncol_new[j]) " in " tolower(newt)
        if (naff_new[col[t, j]] != aff[t, j])
            return tolower(col[t, j]) " changes type affinity from " aff[t, j] " to " naff_new[col[t, j]] ", which can convert values"
    }

    # With foreign keys on, DROP TABLE deletes every row first, and a
    # cascading or nulling foreign key carries that into the child table.
    for (k = 0; k <= last; k++) {
        fk = 0
        for (i = 1; i < sn[k]; i++) if (kw(k, i, "REFERENCES") && getname(k, i + 1) && NAME == t) fk = 1
        if (!fk) continue
        for (i = 1; i < sn[k] - 1; i++)
            if (kw(k, i, "ON") && kw(k, i + 1, "DELETE") && (kw(k, i + 2, "CASCADE") || kw(k, i + 2, "SET")))
                return "a foreign key at " where(k) " references " tolower(t) " with ON DELETE " T[k, i + 2]
    }

    # land exempts the DROP by its line, so the line must hold the DROP alone.
    if (sstart[kd] != send[kd] || split(lstmts[tf, sstart[kd]], lst, " ") != 1)
        return "the DROP of " tolower(t) " does not stand alone on its line"

    cols = ""
    for (j = 1; j <= ncol[t] && j <= 8; j++) cols = cols (j > 1 ? ", " : "") tolower(col[t, j])
    if (ncol[t] > 8) cols = cols ", ..."
    return sprintf("ok\t%s\t%d\t%s copies all %d columns of %s (%s) with no filter", tolower(t), sstart[kd], tolower(newt), ncol[t], tolower(t), cols)
}
