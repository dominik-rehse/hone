#!/bin/bash
# PreToolUse guard for Bash commands (Claude Code).
#
# Tamper resistance for hone's enforcement. The Write/Edit deny rules in
# settings.json stop the file tools. This hook closes the obvious SHELL routes
# around them and around the gate. The threat model is a friction-avoiding agent
# that takes an open path, not an adversary. So this hook is a DETERRENT, not a
# sandbox: multi-step obfuscation (write-a-script-then-run-it, `python -c`,
# base64) can still evade string matching. It deters and makes tampering
# attributable.
#
#   deny: unambiguous attempts to disable the gate or its markers
#   ask:  a mutating op aimed at a protected artifact, at the primary tree, or
#         at the primary branch itself (escalate to the human)
#
# The same .hone-off marker that disables the rest of hone disables this hook.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/messages.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0
[ -f ".hone-off" ] && exit 0

# $1 = deny|ask, $2 = a template from messages.sh (already prefixed).
decision() { hone_pretool_decision "$1" "$2"; exit 0; }

# Sabotage tokens. Both scan paths share this one definition, so the two cannot
# drift. HARD_TOKENS always mean "disable the whole gate": sabotage on any path.
# MARKER_TOKENS are context-dependent. CREATING .hone-off disables hone, and
# HAND-WRITING a grant or proof sign-off bypasses the helpers that make the
# record readable. The constructs below deny both. Reading or removing one is
# legitimate, so a bare mention only escalates on the fail-closed backstop, and
# never auto-denies.
HARD_TOKENS='--no-verify|core\.hooksPath'
MARKER_TOKENS='\.hone-off|\.hone-(grant|proof)/'

INPUT=$(cat)
CMD=$(hone_extract_field "$INPUT" command)

# Every scan below is case-insensitive (grep -i). Git reads a config key in
# any case, so `core.hookspath=` disables the hooks exactly as `core.hooksPath=`
# does, and a case-sensitive scan let the lowercase spelling through.

if [ -z "$CMD" ]; then
    # Parsing failed. Fail closed: if the raw payload carries any gate-sabotage
    # token, escalate. Otherwise nothing is actionable, so allow.
    if echo "$INPUT" | grep -Eiq "$HARD_TOKENS|$MARKER_TOKENS"; then
        decision ask "$(msg_bashguard_unparsed)"
    fi
    exit 0
fi

# Strip the prose out of the command before any rule reads it. A commit
# message and a land-gate sign-off text are prose by construction, and prose
# names whatever it explains: a commit that documents the --no-verify deny
# rule, a grant that says what `git reset --hard` cannot undo, a message
# mentioning `bun add`. Every rule below used to read those as the act itself,
# and each false deny or ask stopped an unattended run.
#
# The cut is narrow on purpose. It removes the VALUE of a git -m/--message
# option (quoted, or one bare word) and the free text after `worktree.sh grant
# <change>` or `attest <change>`. It never blanks a quoted string anywhere
# else, because a quoted path is a real target (`tee "scripts/lint.sh"`), and
# a rule that read past it would fail open. The residual hole is a command
# substitution inside the message itself, which the helper text and a heredoc
# body can carry. That is multi-step obfuscation, and this hook is a
# deterrent, not a sandbox (see the header).
#
# `sed -z` reads the whole command as one record, so a heredoc message body
# spanning several lines is one quoted value. A message whose quoting this
# pattern cannot follow stays as it is, and the rules then read it as before.
# The failure mode is a false ask, never a missed write.
CMD=$(printf '%s' "$CMD" | sed -Ez \
    -e "s/(^|[[:space:]])(-[A-Za-z]*m|--message)([[:space:]]*|=)(\"[^\"]*\"|'[^']*'|[^[:space:]\"'][^[:space:]]*)/\\1\\2\\3''/g" \
    -e 's/(worktree\.sh[[:space:]]+(grant|attest)[[:space:]]+[^[:space:]|;&]+)[^|;&]*/\1/g')

# 1. Unambiguous gate / marker sabotage → deny: a hard token, or a shell
# construct that CREATES .hone-off.
#
# Only CREATION counts. `echo` and `printf` used to match on a bare mention of
# the marker, so the guard denied a read-only existence check (`ls .../.hone-off
# || echo "no .hone-off marker present"`) as sabotage. The redirect rule below
# already catches every command that writes the marker, whichever program
# produces the text. So the two creation verbs that write no redirect (touch,
# install) are the whole list.
if echo "$CMD" | grep -Eiq \
        -e "$HARD_TOKENS" \
        -e '(^|[^A-Za-z_])(HUSKY|LEFTHOOK|GIT_CONFIG[A-Z_]*)=' \
        -e '(touch|install)[^|;&]*\.hone-off' \
        -e '>[[:space:]]*[^|;&[:space:]]*\.hone-off'; then
    decision deny "$(msg_bashguard_sabotage)"
fi

SHELL_CWD=$(hone_extract_top_field "$INPUT" cwd)
[ -n "$SHELL_CWD" ] && [ -d "$SHELL_CWD" ] || SHELL_CWD="$PWD"

# ------------------------------------------------------------------------
# THE COMMAND'S STRUCTURE. Every rule below reads the command one simple
# command at a time, in the tree that command runs in. A whole-line match
# read too much. A `git -C "$SCRATCH" merge` in a scratch worktree asked as a
# primary-branch move. A `ls .hone-grant/` inside `$(...)` behind an `echo`
# was denied as a write. A heredoc commit message that named `git -C <primary
# tree>` and a package install asked as the install. About eleven of fourteen
# field asks on the primary-branch rule were false, and one sat forty
# minutes.
#
# hone_cmd_segments (awk) splits the command at `;`, `&&`, `||`, `|`, `&`, and
# newlines, outside quotes. A subshell `( ... )`, a command substitution, and
# a process substitution open a group whose `cd` does not persist. The
# substitution's body is its own segments, and the enclosing segment keeps a
# masked copy with the body replaced, for the rules to read. A heredoc body
# becomes body lines, which only the write rules read, and a comment goes.
# Each record is "kind \037 fields", ended by \036:
#
#   s  raw \037 masked \037 word \037 word ...   one simple command
#   o / c                                         a group opens / closes
#   b  line                                       one heredoc body line
#   u                                             unbalanced quotes or groups
#
# The walker below replays the segments in order. It tracks the directory
# each one runs in (a `cd`, a `pushd`, a subshell), the variables the command
# assigns itself (a literal path, `$(mktemp -d)`, `$(pwd)`), and the trees it
# creates (`mkdir`, `git worktree add`). A git command runs in its `-C`,
# `--git-dir`, or `--work-tree` path. Anything it cannot resolve is an
# unknown tree, and an unknown tree counts as the primary tree: the rules
# fail closed. An unbalanced parse makes every tree unknown.
hone_cmd_segments() {
    printf '%s' "$1" | awk '
    function add(x) {
        SR[d] = SR[d] x; SM[d] = SM[d] x; CW[d] = CW[d] x
        if (d > 0) FULL[d] = FULL[d] x
    }
    function sp(x) {
        endword(); SR[d] = SR[d] x; SM[d] = SM[d] x
        if (d > 0) FULL[d] = FULL[d] x
    }
    function endword() {
        if (CW[d] != "") { WS[d] = WS[d] "\037" CW[d]; CW[d] = "" }
    }
    function flush() {
        endword()
        if (SR[d] ~ /[^ \t\n]/) printf "s\037%s\037%s%s\036", SR[d], SM[d], WS[d]
        SR[d] = ""; SM[d] = ""; WS[d] = ""
    }
    function emit(k) { printf "%s\036", k }
    function init(k) { SR[k] = ""; SM[k] = ""; CW[k] = ""; WS[k] = ""; Q[k] = ""; GP[k] = 0; FULL[k] = ""; OP[k] = "" }
    function opensub(op) {
        emit("o"); d++; init(d); OP[d] = op
    }
    function closesub(   op, cl, raw) {
        flush(); emit("c")
        op = OP[d]; cl = (op == "`") ? "`" : ")"
        raw = op FULL[d] cl
        d--
        SR[d] = SR[d] raw; SM[d] = SM[d] op "…" cl; CW[d] = CW[d] raw
        if (d > 0) FULL[d] = FULL[d] raw
    }
    BEGIN { RS = "\001" }
    {
        s = $0; n = length(s); d = 0; init(0); nh = 0; bad = 0
        i = 1
        while (i <= n) {
            c = substr(s, i, 1); c2 = substr(s, i, 2)
            q = Q[d]
            if (q == "\047") { add(c); if (c == "\047") Q[d] = ""; i++; continue }
            if (c == "\\") { add(substr(s, i, 2)); i += 2; continue }
            if (q == "\"") {
                if (c == "\"") { add(c); Q[d] = ""; i++; continue }
                if (c2 == "$(") { opensub("$("); i += 2; continue }
                if (c == "`") { if (OP[d] == "`") { closesub(); i++; continue } opensub("`"); i++; continue }
                add(c); i++; continue
            }
            if (c == "`" && OP[d] == "`") { closesub(); i++; continue }
            if (c == "\047" || c == "\"") { add(c); Q[d] = c; i++; continue }
            if (c2 == "$(" || c2 == "<(" || c2 == ">(") { opensub(c2); i += 2; continue }
            if (c == "`") { opensub("`"); i++; continue }
            if (c == "(") { flush(); emit("o"); GP[d]++; i++; continue }
            if (c == ")") {
                if (GP[d] > 0) { flush(); emit("c"); GP[d]--; i++; continue }
                if (d > 0 && OP[d] != "`") { closesub(); i++; continue }
                flush(); i++; continue
            }
            if (c == "#" && CW[d] == "") {
                while (i <= n && substr(s, i, 1) != "\n") i++
                continue
            }
            if (c2 == "<<" && substr(s, i + 2, 1) != "<") {
                j = i + 2; strip = 0
                if (substr(s, j, 1) == "-") { strip = 1; j++ }
                while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
                delim = ""; qc = substr(s, j, 1)
                if (qc == "\047" || qc == "\"") {
                    j++
                    while (j <= n && substr(s, j, 1) != qc) { delim = delim substr(s, j, 1); j++ }
                    j++
                } else {
                    while (j <= n && substr(s, j, 1) !~ /[ \t\n;&|<>()]/) { delim = delim substr(s, j, 1); j++ }
                    gsub(/[\\\047"]/, "", delim)
                }
                add(substr(s, i, j - i))
                if (delim != "") { nh++; HD[nh] = delim; HS[nh] = strip }
                i = j; continue
            }
            if (c == "\n") {
                flush(); i++
                for (h = 1; h <= nh; h++) {
                    while (i <= n) {
                        e = index(substr(s, i), "\n")
                        line = (e > 0) ? substr(s, i, e - 1) : substr(s, i)
                        i = (e > 0) ? i + e : n + 1
                        cmp = line
                        if (HS[h]) sub(/^\t+/, "", cmp)
                        if (cmp == HD[h]) break
                        printf "b\037%s\036", line
                    }
                }
                nh = 0
                continue
            }
            if (c == "&" && (c2 == "&>" || CW[d] ~ /[<>]$/)) { add(c); i++; continue }
            if (c == ";" || c == "&" || c == "|") {
                flush(); i++
                x = substr(s, i, 1)
                if ((c == "&" && x == "&") || (c == "|" && (x == "|" || x == "&")) || (c == ";" && x == ";")) i++
                continue
            }
            if (c == " " || c == "\t") { sp(c); i++; continue }
            add(c); i++
        }
        if (d > 0 || Q[0] != "" || GP[0] != 0) bad = 1
        while (d > 0) { closesub() }
        flush()
        if (bad) emit("u")
    }'
}

# The primary tree's git dir, which is also the common dir of every linked
# worktree. Empty outside a repository, where no tree is primary.
OUR_COMMON=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)

# Normalize an absolute path lexically: collapse //, ./, and ../.
hone_norm() {
    local p="$1" out="" part
    local IFS=/
    for part in $p; do
        case "$part" in
            ''|.) ;;
            ..) out=${out%/*} ;;
            *) out="$out/$part" ;;
        esac
    done
    printf '%s' "${out:-/}"
}

# $1 resolved against the directory $2. Fails when $1 is relative and $2 is
# unknown (empty).
hone_resolve() {
    case "$1" in
        /*) hone_norm "$1" ;;
        *) [ -n "$2" ] || return 1; hone_norm "$2/$1" ;;
    esac
}

# The kind of tree an absolute path sits in: primary (this repository's
# primary tree), linked (a linked worktree of it), or other (anywhere else).
# A path this command creates with `git worktree add` is linked. A path that
# does not exist yet is judged by its nearest existing ancestor.
TK_KEYS=(); TK_VALS=()
WT_NEW=()
hone_tree_kind() {
    local p="$1" a w i kind
    for w in "${WT_NEW[@]+"${WT_NEW[@]}"}"; do
        case "$p" in "$w"|"$w"/*) echo linked; return 0 ;; esac
    done
    for i in "${!TK_KEYS[@]}"; do
        [ "${TK_KEYS[$i]}" = "$p" ] && { echo "${TK_VALS[$i]}"; return 0; }
    done
    a=$p
    while [ ! -d "$a" ]; do a=${a%/*}; [ -n "$a" ] || a=/; done
    kind=$(
        cd "$a" 2>/dev/null || { echo other; exit 0; }
        g=$(git rev-parse --git-dir 2>/dev/null) || { echo other; exit 0; }
        c=$(git rev-parse --git-common-dir 2>/dev/null)
        g=$(cd "$g" 2>/dev/null && pwd -P)
        c=$(cd "$c" 2>/dev/null && pwd -P)
        if [ -z "$OUR_COMMON" ] || [ "$c" != "$OUR_COMMON" ]; then echo other
        elif [ "$g" = "$c" ]; then echo primary
        else echo linked
        fi
    )
    TK_KEYS+=("$p"); TK_VALS+=("$kind")
    echo "$kind"
}

# True when the tree $1 (an absolute path, or empty for unknown) counts as
# the primary tree for rules 3 and 4. Unknown fails closed, inside a
# repository.
hone_tree_primary() {
    [ -n "$OUR_COMMON" ] || return 1
    [ "$PARSE_BAD" -eq 0 ] || return 0
    [ -n "$1" ] || return 0
    [ "$(hone_tree_kind "$1")" = primary ]
}

# True when path $1 (absolute, or empty for unknown) lies in any tree of this
# repository, for the check-config rule. Outside a repository, the project
# directory counts.
hone_path_inside() {
    [ "$PARSE_BAD" -eq 0 ] || return 0
    [ -n "$1" ] || return 0
    if [ -z "$OUR_COMMON" ]; then
        case "$1" in "$PROJECT_ROOT"|"$PROJECT_ROOT"/*) return 0 ;; esac
        return 1
    fi
    [ "$(hone_tree_kind "$1")" != other ]
}

# The command's own variables: parallel arrays, name and value. The value
# \001 marks a variable the walker cannot resolve.
VN=(); VV=()
hone_var_set() {
    local i
    for i in "${!VN[@]}"; do
        [ "${VN[$i]}" = "$1" ] && { VV[$i]=$2; return 0; }
    done
    VN+=("$1"); VV+=("$2")
}
hone_var_get() {
    local i
    for i in "${!VN[@]}"; do
        [ "${VN[$i]}" = "$1" ] || continue
        [ "${VV[$i]}" = $'\001' ] && return 1
        printf '%s' "${VV[$i]}"; return 0
    done
    case "$1" in
        HOME) printf '%s' "$HOME" ;;
        PWD) [ -n "$CUR" ] || return 1; printf '%s' "$CUR" ;;
        *) return 1 ;;
    esac
}

# The value of shell word $1, quotes removed and the command's own variables
# expanded, in WV. Fails on anything else the shell would expand: a command
# substitution, a positional or unknown variable, a parameter operator.
hone_word_value() {
    local w="$1" out="" q="" c i=0 name val
    case "$w" in *'$('*|*'`'*|*'<('*|*'>('*) return 1 ;; esac
    # shellcheck disable=SC2088  # the literal tilde is what is matched
    case "$w" in "~"|"~/"*) w="$HOME${w#\~}" ;; esac
    while [ "$i" -lt "${#w}" ]; do
        c=${w:i:1}
        if [ "$q" = "'" ]; then
            if [ "$c" = "'" ]; then q=""; else out+=$c; fi
            i=$((i+1)); continue
        fi
        case "$c" in
            "'") if [ -z "$q" ]; then q="'"; else out+=$c; fi ;;
            '"') if [ "$q" = '"' ]; then q=""; else q='"'; fi ;;
            '\') i=$((i+1)); out+=${w:i:1} ;;
            '$')
                if [ "${w:i+1:1}" = "{" ]; then
                    name=${w:i+2}; name=${name%%\}*}
                    [ "${w:i+2+${#name}:1}" = "}" ] || return 1
                    i=$((i+2+${#name}))
                else
                    name=${w:i+1}; name=${name%%[!A-Za-z0-9_]*}
                    [ -n "$name" ] || { out+=$c; i=$((i+1)); continue; }
                    i=$((i+${#name}))
                fi
                case "$name" in [A-Za-z_]*) ;; *) return 1 ;; esac
                case "$name" in *[!A-Za-z0-9_]*) return 1 ;; esac
                val=$(hone_var_get "$name") || return 1
                out+=$val ;;
            *) out+=$c ;;
        esac
        i=$((i+1))
    done
    [ -z "$q" ] || return 1
    WV=$out
}

# The value an assignment word's right-hand side $1 gives, for hone_var_set:
# a literal (with the command's variables expanded), a fresh directory from
# `$(mktemp -d ...)`, or `$(pwd)`. \001 for anything else.
hone_assign_value() {
    local v="$1" inner dir="" t tpl="" tflag=0 prev=""
    case "$v" in
        '$(mktemp'*')'|'"$(mktemp'*')"')
            inner=${v#\"}; inner=${inner%\"}; inner=${inner#\$(mktemp}; inner=${inner%)}
            case " $inner " in *" -d "*|*" --directory "*|*" -"[a-z]*d[a-z]*" "*) ;; *) printf '\001'; return ;; esac
            for t in $inner; do
                case "$prev" in -p|--tmpdir) dir=$t ;; esac
                case "$t" in
                    -t) tflag=1 ;;
                    --tmpdir=*) dir=${t#--tmpdir=} ;;
                    -*) ;;
                    *) [ "$prev" = -p ] || [ "$prev" = --tmpdir ] || tpl=$t ;;
                esac
                prev=$t
            done
            case "$dir$tpl" in *'$'*|*'`'*) printf '\001'; return ;; esac
            if [ -n "$dir" ]; then :
            elif [ -n "$tpl" ] && [ "$tflag" -eq 0 ]; then
                case "$tpl" in */*) dir=${tpl%/*} ;; *) dir=$CUR ;; esac
            else
                dir=${TMPDIR:-/tmp}
            fi
            [ -n "$dir" ] || { printf '\001'; return; }
            dir=$(hone_resolve "$dir" "$CUR") || { printf '\001'; return; }
            # A fresh directory that does not exist yet. Its tree is its
            # parent's, and a cd into it succeeds.
            MADE+=("$dir/tmp.mktemp")
            printf '%s' "$dir/tmp.mktemp"; return ;;
        '$(pwd)'|'"$(pwd)"'|'`pwd`')
            [ -n "$CUR" ] && { printf '%s' "$CUR"; return; }
            printf '\001'; return ;;
    esac
    hone_word_value "$v" || { printf '\001'; return; }
    printf '%s' "$WV"
}

# True when directory $1 exists, or this command creates it first.
MADE=()
hone_dir_ready() {
    local m
    [ -d "$1" ] && return 0
    for m in "${MADE[@]+"${MADE[@]}"}" "${WT_NEW[@]+"${WT_NEW[@]}"}"; do
        [ "$m" = "$1" ] && return 0
    done
    return 1
}

# The walk. Its results feed the rules below:
#   SEGS / TREES / CURS / FIRSTS   one entry per simple command: the masked
#                                  text, the tree its git runs in, the
#                                  directory it runs in, and its words
#   BODIES / BODY_CURS             heredoc body lines, with their directory
PARSE_BAD=0
CUR=$SHELL_CWD
SEGS=(); TREES=(); CURS=(); WORDS_OF=()
BODIES=(); BODY_CURS=()
STACK=(); STACKV=()
while IFS= read -r -d $'\036' rec; do
    kind=${rec%%$'\037'*}
    case "$kind" in
        o) STACK+=("$CUR"); STACKV+=("${#VN[@]}"); continue ;;
        c)
            if [ "${#STACK[@]}" -gt 0 ]; then
                CUR=${STACK[${#STACK[@]}-1]}; unset "STACK[${#STACK[@]}-1]"
                nv=${STACKV[${#STACKV[@]}-1]}; unset "STACKV[${#STACKV[@]}-1]"
                VN=("${VN[@]:0:$nv}"); VV=("${VV[@]:0:$nv}")
            fi
            continue ;;
        u) PARSE_BAD=1; continue ;;
        b) BODIES+=("${rec#b$'\037'}"); BODY_CURS+=("$CUR"); continue ;;
    esac
    rest=${rec#s$'\037'}
    rest=${rest#*$'\037'}      # the raw text; the rules read the masked copy
    mask=${rest%%$'\037'*}
    words=()
    if [ "$rest" != "$mask" ]; then
        rest=${rest#*$'\037'}
        while :; do
            words+=("${rest%%$'\037'*}")
            [ "$rest" = "${rest#*$'\037'}" ] && break
            rest=${rest#*$'\037'}
        done
    fi
    nw=${#words[@]}
    # Skip the words that only prefix a command.
    k=0
    while [ "$k" -lt "$nw" ]; do
        case "${words[$k]}" in
            '!'|'{'|'}'|do|then|else|elif|if|while|until|time|sudo|command|builtin|exec|nohup) k=$((k+1)) ;;
            *) break ;;
        esac
    done
    # Assignments. Alone, they persist. Before a command, they are its
    # environment only.
    a=$k
    while [ "$a" -lt "$nw" ] && [[ "${words[$a]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do a=$((a+1)); done
    case "${words[$a]:-}" in
        export|readonly|declare|typeset|local)
            j=$((a+1))
            while [ "$j" -lt "$nw" ]; do
                if [[ "${words[$j]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                    hone_var_set "${words[$j]%%=*}" "$(hone_assign_value "${words[$j]#*=}")"
                fi
                j=$((j+1))
            done ;;
    esac
    if [ "$a" -eq "$nw" ]; then
        j=$k
        while [ "$j" -lt "$nw" ]; do
            v=$(hone_assign_value "${words[$j]#*=}")
            case "$v" in */tmp.mktemp) MADE+=("$v") ;; esac
            hone_var_set "${words[$j]%%=*}" "$v"
            j=$((j+1))
        done
    fi
    k=$a
    cmd=""
    [ "$k" -lt "$nw" ] && { hone_word_value "${words[$k]}" && cmd=$WV || cmd=${words[$k]}; }
    tree=$CUR
    case "$cmd" in
        cd|pushd)
            j=$((k+1)); tgt=""
            while [ "$j" -lt "$nw" ]; do
                case "${words[$j]}" in -|-[A-Za-z]*) [ "${words[$j]}" = - ] && { tgt=-; break; } ;; *) tgt=${words[$j]}; break ;; esac
                j=$((j+1))
            done
            if [ -z "$tgt" ]; then CUR=$HOME
            elif [ "$tgt" = - ]; then CUR=""
            elif hone_word_value "$tgt" && p=$(hone_resolve "$WV" "$CUR") && hone_dir_ready "$p"; then CUR=$p
            else CUR=""
            fi
            tree=$CUR ;;
        popd) CUR=""; tree="" ;;
        mkdir)
            j=$((k+1))
            while [ "$j" -lt "$nw" ]; do
                case "${words[$j]}" in
                    -m) j=$((j+1)) ;;
                    -*) ;;
                    *) hone_word_value "${words[$j]}" && p=$(hone_resolve "$WV" "$CUR") && MADE+=("$p") ;;
                esac
                j=$((j+1))
            done ;;
    esac
    # A git command runs where its -C, --git-dir, or --work-tree points.
    g=$k
    while [ "$g" -lt "$nw" ]; do
        case "${words[$g]}" in git|*/git) break ;; esac
        g=$((g+1))
    done
    if [ "$g" -lt "$nw" ]; then
        j=$((g+1)); sub=""
        while [ "$j" -lt "$nw" ]; do
            w=${words[$j]}
            case "$w" in
                -C|--git-dir|--work-tree)
                    j=$((j+1))
                    if [ -n "$tree" ] && hone_word_value "${words[$j]:-}" && p=$(hone_resolve "$WV" "$tree"); then
                        tree=$p
                    elif hone_word_value "${words[$j]:-}" && [ "${WV#/}" != "$WV" ]; then
                        tree=$(hone_norm "$WV")
                    else
                        tree=""
                    fi
                    [ "$w" = --git-dir ] && tree=${tree%/.git} ;;
                --git-dir=*|--work-tree=*)
                    if hone_word_value "${w#*=}" && p=$(hone_resolve "$WV" "$CUR"); then tree=${p%/.git}; else tree=""; fi ;;
                -c) j=$((j+1)) ;;
                -*) ;;
                *) sub=$w; break ;;
            esac
            j=$((j+1))
        done
        # `git worktree add <path>` makes a linked worktree there.
        if [ "$sub" = worktree ] && [ "${words[$((j+1))]:-}" = add ]; then
            j=$((j+2))
            while [ "$j" -lt "$nw" ]; do
                case "${words[$j]}" in
                    -b|-B|--reason) j=$((j+1)) ;;
                    -*) ;;
                    *)
                        if hone_word_value "${words[$j]}" && p=$(hone_resolve "$WV" "${tree:-}"); then
                            WT_NEW+=("$p"); TK_KEYS=(); TK_VALS=()
                        fi
                        break ;;
                esac
                j=$((j+1))
            done
        fi
    fi
    SEGS+=("$mask"); TREES+=("$tree"); CURS+=("$CUR")
    wl=""
    for w in "${words[@]:$k}"; do wl+="$w"$'\037'; done
    WORDS_OF+=("$wl")
done < <(hone_cmd_segments "$CMD")

# 1b. HAND-WRITING an authority grant or a proof sign-off → deny. The helpers
# (worktree.sh grant and attest) are the only route to these files, for the
# agent as much as for a person. They are what stamps the signer, binds a
# sign-off to the commit it proves, and refuses an empty or placeholder text.
# A raw write past them produces a file the gate may accept and no reader can
# trust. So every shell route to the file itself stays denied. The rule allows
# the helpers themselves.
# The mutating-op list is a superset of rule 2's below (creation verbs plus
# every mutator). So a token rule 2 treats as a write cannot pass here.
#
# It reads each simple command, the body of each substitution, and each
# heredoc body line on its own, so a read inside `$(...)` is not the write of
# the `echo` around it. An unbalanced parse reads the whole command.
SIGNOFF_RE1='(touch|install|printf|echo|tee|cp|mv|mkdir|ln|sed -i|rm |truncate|dd|chmod|chattr)[^|;&]*\.hone-(grant|proof)/'
SIGNOFF_RE2='>>?[[:space:]]*"?'"'"'?[^[:space:]|;&]*\.hone-(grant|proof)/'
if [ "$PARSE_BAD" -eq 1 ]; then
    SIGNOFF_TEXT=$CMD
else
    SIGNOFF_TEXT=$(printf '%s\n' "${SEGS[@]+"${SEGS[@]}"}" "${BODIES[@]+"${BODIES[@]}"}")
fi
if printf '%s\n' "$SIGNOFF_TEXT" | grep -Eq -e "$SIGNOFF_RE1" -e "$SIGNOFF_RE2"; then
    decision deny "$(msg_bashguard_signoff)"
fi

# 1c. The proof sign-off is the human's act, so `worktree.sh attest` stays
# denied to the agent whatever text follows it. The run runs the check where
# it can and hands the human its output, and the human signs. `grant` stays
# allowed: the authority gate asks for a reading of the diff, and the stamp
# says who read it. The sed above already stripped attest's free text, so
# this matches the invocation alone, never a mention inside a message.
if echo "$CMD" | grep -Eq 'worktree\.sh"?[[:space:]]+attest([[:space:]]|$)'; then
    decision deny "$(msg_bashguard_attest)"
fi

# 2. A mutating operation aimed at a protected artifact → ask. The committed
# policy files are protected too. Editing .hone-durable-paths,
# .hone-irreversible-paths, the .hone-proof-always marker, or the
# .hone-review-always list shrinks or widens the enforcement perimeter, which is
# the human's call. Deleting the marker is the cheapest way past the land proof
# gate, and deleting the list is the cheapest way past a review. So both
# escalate like the rest. .hone-shared is in the set too: deleting it is the
# cheapest way past a push the host refused, and it decides where the team
# lands.
#
# The two constructs need different shapes, so they get one pattern each.
#
# A REDIRECT writes to the path that follows it, with nothing in between. So it
# binds tightly, the way rule 1b already writes it. One loose rule for both
# constructs read any '>' anywhere in the line as a write into any protected
# path later in the line. A quoted message is prose, and prose carries angle
# brackets: `attest <change> "ran PROOF_ROOT=<worktree> bash scripts/proof.sh"`
# escalated on its own text. That ask stopped two unattended runs for 16 and 48
# minutes, on the one helper the agent is meant to call by itself.
#
# A VERB takes a source and a target, so it keeps the loose gap.
#
# The ask names the file. An unnamed ask was approved by a person who did not
# know which file it meant.
PROT='scripts/run-tests\.sh|scripts/typecheck\.sh|scripts/lint\.sh|scripts/proof\.sh|hooks/(guard|gate|nag|bash-guard|session-start|common|messages)\.sh|\.claude/settings(\.local)?\.json|\.hone-durable-paths|\.hone-(irreversible|consequential)-paths|\.hone-proof-always|\.hone-review-always|\.hone-shared'
REDIR_PRE=">>?[[:space:]]*\"?'?[^[:space:]|;&]*"
VERB_PRE='(tee|sed -i|cp |mv |install |ln -s|chmod|chattr|rm |truncate|dd of=)[^|;&]*'
hit=$(printf '%s\n' "$CMD" | grep -Eo -e "${REDIR_PRE}(${PROT})" -e "${VERB_PRE}(${PROT})" | head -n 1)
if [ -n "$hit" ]; then
    decision ask "$(msg_bashguard_protected "$(printf '%s\n' "$hit" | grep -Eo "(${PROT})" | tail -n 1)")"
fi

# 2b. The check configs are protected for the same reason (HONE_CHECK_CONFIG_RE
# in common.sh, shared with guard.sh rule 1b). The gate's test, lint, format,
# and type-check runs are only as strict as the config they read, so an edit
# there turns a red check green without touching the code. The pattern matches
# the basename with no left boundary, so a nested config in a monorepo counts.
#
# It asks in any tree of this repository, and passes outside it. A scratch
# config for a one-off run, such as a mutation check, belongs outside the
# repository, where no gate reads it. The ask used to fire on a scratch
# mutation-check config wherever it went, and unattended runs stalled on it
# for up to seven hours. The walk resolves each path against the directory its
# command runs in. A path it cannot resolve asks.
CFG="${HONE_CHECK_CONFIG_RE}([^A-Za-z0-9_.-]|$)"
CFG_WORD="^(.*/)?${HONE_CHECK_CONFIG_RE}\$"
CFG_SEEN=0
RE_CFG_REDIR="${REDIR_PRE}(${CFG})"
RE_CFG_VERB="${VERB_PRE}(${CFG})"
# Ask about config path $1 (a shell word) in directory $2, when it is inside.
hone_cfg_judge() {
    local p
    if hone_word_value "$1" && p=$(hone_resolve "${WV#of=}" "$2"); then
        hone_path_inside "$p" || return 0
        decision ask "$(msg_bashguard_check_config "${WV#of=}")"
    fi
    decision ask "$(msg_bashguard_check_config "$1")"
}
if [ "$PARSE_BAD" -eq 0 ]; then
    for i in "${!SEGS[@]}"; do
        seg=${SEGS[$i]}
        [[ $seg =~ $RE_CFG_REDIR || $seg =~ $RE_CFG_VERB ]] || continue
        CFG_SEEN=1
        # A redirect target.
        while IFS= read -r tok; do
            tok=${tok#>}; tok=${tok#>}; tok=${tok#"${tok%%[![:space:]]*}"}
            if hone_word_value "$tok"; then
                [[ $WV =~ $CFG_WORD ]] || continue
            else
                [[ $tok =~ $CFG ]] || continue
            fi
            hone_cfg_judge "$tok" "${CURS[$i]}"
        done < <(printf '%s\n' "$seg" | grep -Eo ">>?[[:space:]]*(\"[^\"]*\"|'[^']*'|[^[:space:]|;&<>]+)")
        # A verb's operands. cp, install, and ln write only their last one,
        # which may be a directory.
        [[ $seg =~ $RE_CFG_VERB ]] || continue
        IFS=$'\037' read -r -a ws <<<"${WORDS_OF[$i]%$'\037'}"
        verb=${ws[0]:-}
        case "$verb" in
            cp|install|ln)
                last=${ws[${#ws[@]}-1]}
                hone_cfg_judge "$last" "${CURS[$i]}" ;;
            *)
                for w in "${ws[@]:1}"; do
                    if hone_word_value "$w"; then
                        [[ ${WV#of=} =~ $CFG_WORD ]] || continue
                    else
                        [[ $w =~ $CFG ]] || continue
                    fi
                    hone_cfg_judge "$w" "${CURS[$i]}"
                done ;;
        esac
    done
    for i in "${!BODIES[@]}"; do
        hit=$(printf '%s\n' "${BODIES[$i]}" | grep -Eo -e "${REDIR_PRE}(${CFG})" -e "${VERB_PRE}(${CFG})" | head -n 1)
        [ -n "$hit" ] && decision ask "$(msg_bashguard_check_config "$(printf '%s\n' "$hit" | grep -Eo "${HONE_CHECK_CONFIG_RE}" | tail -n 1)")"
    done
fi
# Fail closed: a config write the walk did not see is still asked about.
if [ "$CFG_SEEN" -eq 0 ]; then
    hit=$(printf '%s\n' "$CMD" | grep -Eo -e "${REDIR_PRE}(${CFG})" -e "${VERB_PRE}(${CFG})" | head -n 1)
    [ -n "$hit" ] && decision ask "$(msg_bashguard_check_config "$(printf '%s\n' "$hit" | grep -Eo "${HONE_CHECK_CONFIG_RE}" | tail -n 1)")"
fi

# Rules 3 and 4 apply to the primary tree alone, and the walk above says which
# tree each simple command runs in. It starts from the directory the SHELL
# stands in, which is not the one the hook stands in. The hook process starts
# in the directory the session started in, and it stays there. `cd "$WT"`
# moves the shell, and every later Bash call runs in the worktree while the
# hook still stands in the primary tree.
#
# The harness reports the shell's directory in the top-level `cwd` field of the
# hook input, and updates it after each `cd`. Reading it is what lets the run
# loop cd into its worktree once (skills/run/SKILL.md step 1) and work there.
# The walk falls back to the hook's own cwd when the field is absent or names
# no directory (an older harness, a hand-driven test).
#
# git-dir == common-dir ⇔ a tree is the primary tree, not a linked worktree
# (whose git-dir sits under .git/worktrees/). So neither rule fires for work
# in a worktree, which is where both operations are safe and belong, or for
# work outside this repository: a scratch clone, a session scratchpad.

# 3. A HEAD-moving git op in the PRIMARY tree → ask. The primary tree is a merge
# target kept on the trunk. Landing goes through `worktree.sh land`, which
# serializes the merge under a lock. Moving the shared HEAD by hand (a branch
# switch, a stash, a hard reset) races every other session that shares this
# tree. That is the exact collision this rule guards against. Investigation
# belongs in a throwaway `git worktree add --detach`.
#
# 3a. `git stash` reads in two of its forms and mutates in every other. `list`
# and `show` only read the stash, and the rule used to escalate them with the
# rest. That ask stopped unattended runs on a read, and one agent paged the
# operator to confirm a `git stash list`. Everything else still asks: `pop`,
# `drop`, `clear`, a bare `git stash`, a flags-first form like `git stash
# -u`, and any subcommand this rule does not know. Unknown fails closed.
#
# 3b. `git checkout` moves HEAD in one form and restores files in another. `git
# checkout -- <paths>` and `git checkout <ref> -- <paths>` write files and
# leave HEAD where it is, which is the sanctioned way to undo a bad edit in
# the primary tree. The `--` pathspec separator is the signal. Residual false
# positive: `git checkout <file>` without the separator is indistinguishable
# from `git checkout <branch>` here, so it still asks.
#
# 3c. A command that moves the PRIMARY BRANCH, in the primary tree → ask. Rule
# 3 guards the shared HEAD; this one guards the ref HEAD points at.
# `worktree.sh land` is what moves that ref: it holds the land lock, clears the
# shape, authority, and proof gates, re-runs the whole suite on the merge,
# and publishes only a green one. In pass 2 of the ImpossibleBench probe one run
# made a worktree by hand and fast-forwarded the primary branch itself, with no
# review and no land gate, because no rule named `git merge`.
#
# The verbs bind to a following space or the end of the command, so
# `git merge-base` and `git log --merges` read history and pass. The git prefix
# accepts the global options that take their argument separately. It accepts
# no other token, so `git log --grep=merge x` never reads as a merge.
#
# `git push` counts only when its remote is a local path. Pushing the change
# branch to the team's remote is the loop's own step, and shared-mode land
# makes the primary-branch push itself, inside the lock.
#
# 3d. `git reset` moves the primary branch in every form but a few. Rule 3
# escalates --hard, --merge, and --keep, whose danger is the working tree.
# --soft and --mixed move the branch and leave the tree alone. The forms that
# move nothing unstage: a bare `git reset`, a restore with the `--` pathspec
# separator, and a path-scoped `git reset [-q] <path>...`. One operand is a
# path when git cannot read it as a commit. Everything else asks.
GIT_PRE='git([[:space:]]+(-C[[:space:]]+[^[:space:];&|]+|-c[[:space:]]+[^[:space:];&|]+'
GIT_PRE="$GIT_PRE"'|--git-dir[=[:space:]][^[:space:];&|]+|--work-tree[=[:space:]][^[:space:];&|]+'
GIT_PRE="$GIT_PRE"'|--no-pager|--no-replace-objects|--no-optional-locks))*[[:space:]]+'
BRANCH_MOVERS='(merge|cherry-pick|rebase)([[:space:]]|$)'
BRANCH_MOVERS="$BRANCH_MOVERS"'|branch[[:space:]]+[^|;&]*(-f|--force|-M)([[:space:]]|$)'
BRANCH_MOVERS="$BRANCH_MOVERS"'|update-ref[^|;&]*refs/heads/'
BRANCH_MOVERS="$BRANCH_MOVERS"'|push([[:space:]]+-[^[:space:];&|]+)*[[:space:]]+(\.|\.\.|/|\.\./|~/)'
RE_GIT="(^|[^A-Za-z_])${GIT_PRE}"
RE_HEAD="${RE_GIT}"'(switch([[:space:]]|$)|reset[^|;&]*--(hard|merge|keep))'
RE_STASH="${RE_GIT}"'stash([[:space:]]|$)'
RE_STASH_READ="${RE_GIT}"'stash[[:space:]]+(list|show)([[:space:]]|$)'
RE_CHECKOUT="${RE_GIT}"'checkout([[:space:]]|$)'
RE_DASHDASH='[[:space:]]--([[:space:]]|$)'
RE_MOVER="${RE_GIT}(${BRANCH_MOVERS})"
RE_RESET="${RE_GIT}"'reset([[:space:]]|$)'

# True when the `git reset` in word list $1 (from the command word on) only
# unstages, judged in tree $2.
hone_reset_unstages() {
    local ws w seen=0 n=0 op="" tree="$2"
    IFS=$'\037' read -r -a ws <<<"${1%$'\037'}"
    for w in "${ws[@]}"; do
        if [ "$seen" -eq 0 ]; then [ "$w" = reset ] && seen=1; continue; fi
        case "$w" in
            --) return 0 ;;
            -q|--quiet|--no-refresh|--refresh|-N|--intent-to-add) ;;
            -*) return 1 ;;
            *) n=$((n+1)); op=$w ;;
        esac
    done
    [ "$n" -eq 0 ] && return 0
    [ "$n" -ge 2 ] && return 0
    hone_word_value "$op" || return 1
    [ -n "$tree" ] || return 1
    ! git -C "$tree" rev-parse --verify -q "${WV}^{commit}" >/dev/null 2>&1
}

# The ask for a primary-tree git rule. A tree the walk could not resolve says
# so, because the reader's remedy is to name it.
hone_tree_ask() {
    if [ -z "$2" ] || [ "$PARSE_BAD" -eq 1 ]; then
        decision ask "$(msg_bashguard_tree_unresolved "$3")"
    fi
    decision ask "$($1)"
}

for i in "${!SEGS[@]}"; do
    seg=${SEGS[$i]}
    [[ $seg =~ $RE_GIT ]] || continue
    hone_tree_primary "${TREES[$i]}" || continue
    t=${TREES[$i]}
    if [[ $seg =~ $RE_HEAD ]]; then
        hone_tree_ask msg_bashguard_head_move "$t" "moves HEAD"
    fi
    if [[ $seg =~ $RE_STASH ]] && ! [[ $seg =~ $RE_STASH_READ ]]; then
        hone_tree_ask msg_bashguard_head_move "$t" "moves HEAD"
    fi
    if [[ $seg =~ $RE_CHECKOUT ]] && ! [[ $seg =~ $RE_DASHDASH ]]; then
        hone_tree_ask msg_bashguard_head_move "$t" "moves HEAD"
    fi
    if [[ $seg =~ $RE_MOVER ]]; then
        hone_tree_ask msg_bashguard_branch_move "$t" "moves a branch"
    fi
    if [[ $seg =~ $RE_RESET ]] \
       && ! hone_reset_unstages "${WORDS_OF[$i]}" "$t"; then
        hone_tree_ask msg_bashguard_branch_move "$t" "moves a branch"
    fi
done

# 4. A tool that writes its OWN files, run in the PRIMARY tree → ask. This is
# the preventive half of the primary-tree rule for the shell route, and
# dirty-guard.sh (PostToolUse) is the half that catches what this list misses.
# Rule 2 above cannot see these. A package manager rewrites package.json from
# inside its own process, so the command text carries neither a write construct
# nor the path.
#
# This is an allow-list of names, so it DRIFTS by construction. A new package
# manager, a new migrate subcommand, or a wrapper script that calls one is a
# hole until someone adds it here. That is why it only escalates, and why
# dirty-guard checks the effect instead. Keep the boundary loose: a writer
# anywhere in a simple command, so `bunx biome migrate` and `sudo npm install` both
# match. Accept that prose quoting one of these names also escalates. An
# ask costs one keystroke, and a missed dependency sweep costs a bad commit.
#
# A BARE SYNC INSTALL is the exception: `bun install`, `npm ci`, `poetry
# install`, with flags only, installs what the lockfile already says and writes
# no durable file. It is also the sanctioned next step after a land that changed
# the lockfile, and this rule used to escalate it. dirty-guard sees whatever
# such a command leaves dirty. That check catches any write to a durable path,
# so a preventive ask here gains nothing.
#
# The verb's argument separates the two cases. End of command or flag tokens
# only means sync. A non-flag argument names a package, which mutates the
# manifest. So `npm install lodash`, `bun add x`, and `poetry add y` still
# escalate, as does every add/remove/update/upgrade/link verb below.
NAMED_ARG='([[:space:]]+-[^[:space:];&|]*)*[[:space:]]+[^-[:space:];&|]'
SELF_WRITERS='(npm|pnpm|yarn|bun|deno)[[:space:]]+(add|remove|rm|uninstall|update|upgrade|up|link|pkg)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(npm|pnpm|yarn|bun|deno)[[:space:]]+(install|i|ci)'"$NAMED_ARG"
SELF_WRITERS="$SELF_WRITERS"'|(pip|pip3|uv|poetry|cargo|bundle|gem|mix|composer)[[:space:]]+(add|remove|uninstall|lock|update|upgrade|require|fmt)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(pip|pip3|uv|poetry|cargo|bundle|gem|mix|composer)[[:space:]]+(install|sync|deps\.get)'"$NAMED_ARG"
SELF_WRITERS="$SELF_WRITERS"'|go[[:space:]]+(get|mod)([[:space:]]|$)'

# 4b. A FORMATTER in write mode, in the PRIMARY tree. A formatter differs from
# the package managers above in one way that matters: its command names the
# paths it writes. So the hook can apply the same perimeter the file tools
# already apply. `Write` to `.plans/<change>.md` is allowed in the primary tree,
# because the Plan is the one artifact written outside the loop, and the lint
# gate wants that file formatted before its commit. The formatter run that does
# the formatting is the same write through the shell route. Escalating it asked
# the operator to approve a step the workflow itself requires, fifteen times in
# one week.
#
# So a write-mode formatter passes only when it is SCOPED: at least one path
# argument, and every argument a relative, non-durable path. Everything else
# still asks. That includes a bare `dprint fmt` (it formats docs/), any durable
# path, any flag beyond the write-mode flags themselves (a `--config` swap can
# repoint the tool), a glob in a directory part, and every token this walk does
# not recognise. Fail closed keeps the ask, and only a scoped run earns the
# exemption.
#
# The ask prints msg_bashguard_formatter, not rule 4's message. Scoping the run
# is the remedy here, and a package manager has no such remedy. The shared
# message named the worktree alone, so a bare `dprint fmt` in the primary tree
# sent the operator to a worktree while the one-word fix went unmentioned.
#
# Residual hole: the walk reads a path token as written, and hone_is_durable
# reads a project-relative path. So a formatter run from a SUBDIRECTORY of the
# primary tree judges `notes.md` and not `docs/notes.md`, and the exemption is
# wider there than the file tools' perimeter. dirty-guard.sh reads the effect,
# so it still blocks that write.
FMT_WRITERS='(biome|eslint|prettier|dprint|ruff|black|isort|rustfmt|gofmt|jscodeshift|codemod)[^|;&]*(migrate|--write|--fix|--apply|[[:space:]]-w([[:space:]]|$)|[[:space:]]fmt([[:space:]]|$)|[[:space:]]format([[:space:]]|$))'

# True when segment $1 scopes its formatter to non-durable relative paths.
# A subshell body: `set -f` must not leak, and the tokens must be judged as
# written, not as whatever they happen to glob to in the hook's cwd.
hone_fmt_scoped() (
    set -f
    local tok dir n=0
    for tok in $1; do
        tok=${tok%\"}; tok=${tok#\"}; tok=${tok%\'}; tok=${tok#\'}
        while [ "${tok#./}" != "$tok" ]; do tok=${tok#./}; done
        case "$tok" in
            ''|bunx|npx|sudo|--bun|deno|run|exec|dlx) continue ;;
            biome|eslint|prettier|dprint|ruff|black|isort|rustfmt|gofmt|jscodeshift|codemod) continue ;;
            fmt|format|check|lint|migrate) continue ;;
            --write|--fix|--apply|-w) continue ;;
            [0-9]">"*|">"*|"<"*) continue ;;
            -*) return 1 ;;
            *..*|*'$'*|*'`'*|/*|"~"*|.) return 1 ;;
            */*|*.*)
                case "$tok" in
                    */*) dir=${tok%/*} ;;
                    *) dir='' ;;
                esac
                case "$tok" in
                    *[\*\?\[]*)
                        # A glob is judged by its literal directory part. A glob
                        # in the directory, or a rootless glob, stays an ask.
                        [ -n "$dir" ] || return 1
                        case "$dir" in *[\*\?\[]*) return 1 ;; esac
                        hone_is_durable "$dir/x" && return 1 ;;
                    *)
                        hone_is_durable "$tok" && return 1 ;;
                esac
                n=$((n+1)) ;;
            *) return 1 ;;
        esac
    done
    [ "$n" -ge 1 ]
)


RE_SELF="(^|[^A-Za-z0-9_.-])(${SELF_WRITERS})"
RE_FMT="(^|[^A-Za-z0-9_.-])(${FMT_WRITERS})"

# Both writer rules read the directory the simple command runs in. Rule 4
# reads the command with its redirections removed, so a bare sync install
# followed by `2>&1` stays one. Rule 4b reads its paths with the command's own
# variables expanded, so a formatter on `"$f"` after `f=.plans/x.md` is
# scoped.
for i in "${!SEGS[@]}"; do
    seg=${SEGS[$i]}
    if [[ $seg =~ $RE_SELF ]]; then
        plain=$(printf '%s\n' "$seg" | sed -E \
            -e 's/[0-9]*>&[0-9-]+//g' -e 's/&>>?[[:space:]]*[^[:space:]]+//g' \
            -e 's/[0-9]*>>?[[:space:]]*[^[:space:]]+//g' -e 's/[0-9]*<[[:space:]]*[^[:space:]]+//g')
        if [[ $plain =~ $RE_SELF ]]; then
            hone_tree_primary "${CURS[$i]}" && decision ask "$(msg_bashguard_self_writer)"
        fi
    fi
    if [[ $seg =~ $RE_FMT ]]; then
        hone_tree_primary "${CURS[$i]}" || continue
        IFS=$'\037' read -r -a ws <<<"${WORDS_OF[$i]%$'\037'}"
        expanded=""
        for w in "${ws[@]+"${ws[@]}"}"; do
            if hone_word_value "$w"; then expanded+=" $WV"; else expanded+=" $w"; fi
        done
        hone_fmt_scoped "$expanded" && continue
        decision ask "$(msg_bashguard_formatter)"
    fi
done

exit 0
