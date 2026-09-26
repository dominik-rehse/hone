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
# The analysis below reads the command as the shell will, so it keeps the
# original text and strips nothing.
ORIG_CMD=$CMD
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

# The directory the SHELL stands in (rules 3 and 4 below say why).
SHELL_CWD=$(hone_extract_top_field "$INPUT" cwd)
[ -n "$SHELL_CWD" ] && [ -d "$SHELL_CWD" ] || SHELL_CWD="$PWD"

# The patterns the rules below and the analysis share. Each rule's comment
# says why its pattern reads the way it does.
PROT='scripts/run-tests\.sh|scripts/typecheck\.sh|scripts/lint\.sh|scripts/proof\.sh|hooks/(guard|gate|nag|bash-guard|session-start|common|messages)\.sh|\.claude/settings(\.local)?\.json|\.hone-durable-paths|\.hone-(irreversible|consequential)-paths|\.hone-proof-always|\.hone-review-always|\.hone-shared'
CFG="${HONE_CHECK_CONFIG_RE}([^A-Za-z0-9_.-]|$)"
REDIR_PRE=">>?[[:space:]]*\"?'?[^[:space:]|;&]*"
VERB_PRE='(tee|sed -i|cp |mv |install |ln -s|chmod|chattr|rm |truncate|dd of=)[^|;&]*'
RE_CFG_REDIR="${REDIR_PRE}(${CFG})"
RE_CFG_VERB="${VERB_PRE}(${CFG})"
GIT_PRE='git([[:space:]]+(-C[[:space:]]+[^[:space:];&|]+|-c[[:space:]]+[^[:space:];&|]+'
GIT_PRE="$GIT_PRE"'|--git-dir[=[:space:]][^[:space:];&|]+|--work-tree[=[:space:]][^[:space:];&|]+'
GIT_PRE="$GIT_PRE"'|--no-pager|--no-replace-objects))*[[:space:]]+'
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
RE_PUSH="${RE_GIT}"'push([[:space:]]|$)'
RE_RESET="${RE_GIT}"'reset([[:space:]]|$)'
RE_RESET_BARE="${RE_GIT}"'reset[[:space:]]*$'
RE_REF_MOVER="${RE_GIT}"'(branch[[:space:]]+[^|;&]*(-f|--force|-M|-m|--move|-D|-d|--delete)([[:space:]]|$)|update-ref)'
NAMED_ARG='([[:space:]]+-[^[:space:];&|]*)*[[:space:]]+[^-[:space:];&|]'
SELF_WRITERS='(npm|pnpm|yarn|bun|deno)[[:space:]]+(add|remove|rm|uninstall|update|upgrade|up|link|pkg)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(npm|pnpm|yarn|bun|deno)[[:space:]]+(install|i|ci)'"$NAMED_ARG"
SELF_WRITERS="$SELF_WRITERS"'|(pip|pip3|uv|poetry|cargo|bundle|gem|mix|composer)[[:space:]]+(add|remove|uninstall|lock|update|upgrade|require|fmt)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(pip|pip3|uv|poetry|cargo|bundle|gem|mix|composer)[[:space:]]+(install|sync|deps\.get)'"$NAMED_ARG"
SELF_WRITERS="$SELF_WRITERS"'|go[[:space:]]+(get|mod)([[:space:]]|$)'
RE_SELF="(^|[^A-Za-z0-9_.-])(${SELF_WRITERS})"
FMT_WRITERS='(biome|eslint|prettier|dprint|ruff|black|isort|rustfmt|gofmt|jscodeshift|codemod)[^|;&]*(migrate|--write|--fix|--apply|[[:space:]]-w([[:space:]]|$)|[[:space:]]fmt([[:space:]]|$)|[[:space:]]format([[:space:]]|$))'
RE_FMT="(^|[^A-Za-z0-9_.-])(${FMT_WRITERS})"

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

# ------------------------------------------------------------------------
# THE ANALYSIS. The rules below read the whole command as one line, and that
# stays the default and the fail-closed backstop. Read that way, a merge in a
# scratch worktree outside the repository asked as a move of the primary
# branch: about eleven of fourteen field asks on that rule were false, and one
# sat forty minutes. A scratch check config written outside the repository
# asked too, and unattended runs stalled on it for hours.
#
# So where a rule would ask or deny, it first asks this analysis. The analysis
# can only turn that ask into an allow, and only when it understands the whole
# command. Anything it does not model leaves the old decision standing. It
# parses the command into simple commands and replays them in order. It tracks
# the directory each one runs in, the command's own variables, and the
# worktrees it adds. A git command is judged in the tree its -C path names,
# and a push by the repository it writes to.
#
# Rule 5 at the end also runs it on a guarded command that no rule caught,
# and there it can add an ask (rule 5 says when).
#
# It gives up (and the old rule decides) on:
#   - `&`, `if`/`for`/`while`/`case`, functions, `{ }`, backticks, arithmetic,
#     `eval`, `source`, `exec`, `read`, and any other builtin that moves the
#     shell or sets a variable in a way it does not track
#   - a `cd`, `export`, or assignment inside a pipeline or after `||`
#   - a cd target it cannot resolve to an existing directory, a fresh
#     `$(mktemp -d)`, the one directory an `ls -d <glob>` finds, or a
#     worktree the same `&&` chain adds; a path with `..`
#   - `git --git-dir`, `--work-tree`, `-c`, and a push option that names
#     another repository or program
#   - a git, package-manager, or formatter command named inside another
#     command (`bash -c`, `env -C`, `xargs`, `sudo`, an echo), or in a heredoc
#     body that is not a commit message
#   - a symlink the command creates, and a word that names a `.git` path
#
# A cd after an uncertain command in an `&&` chain counts as maybe-run: the
# next list runs in either directory, and both are judged. A variable set that
# way is unknown after the chain.

read -r -d '' HONE_LEX_AWK <<'AWK'
BEGIN { RS = "\001"; SEP = "\037" }
function emit(r) { OUT[++NO] = r }
function bad(why) { emit("x" SEP why) }
function ch(k) { return substr(s, k, 1) }
function read_heredocs(   h, line, e, cmp, body, found) {
    for (h = 1; h <= NH; h++) {
        body = ""; found = 0
        while (i <= n) {
            e = index(substr(s, i), "\n")
            line = (e > 0) ? substr(s, i, e - 1) : substr(s, i)
            i = (e > 0) ? i + e : n + 1
            cmp = line
            if (HSTRIP[h]) sub(/^\t+/, "", cmp)
            if (cmp == HDELIM[h]) { found = 1; break }
            body = body line "\n"
        }
        if (!found) bad("a heredoc without its delimiter")
        OUT[HIDX[h]] = "h" SEP HQ[h] SEP body
    }
    NH = 0
}
function subst(   start, sr, sm) {
    start = i; i += 2; sr = WR; sm = WM
    emit("o" SEP "$("); if (!scan_list(")")) bad("an unbalanced substitution"); emit("c")
    WR = sr substr(s, start, i - start); WM = sm "$(…)"
}
function param(dq,   j, t) {
    j = index(substr(s, i), "}")
    t = (j > 0) ? substr(s, i, j) : ""
    if (!j || t ~ /[`"]|\$\(/) { bad("a parameter expansion"); i = n + 1; return }
    WR = WR t; WM = WM t; i += j
}
function scan_word(   c, j, t, q) {
    WR = ""; WM = ""
    while (i <= n) {
        c = ch(i)
        if (c ~ /[ \t\n;&|<>()]/) break
        if (c == "\\") {
            if (ch(i + 1) == "\n") { i += 2; continue }
            WR = WR substr(s, i, 2); WM = WM substr(s, i, 2); i += 2; continue
        }
        if (c == "\047") {
            j = index(substr(s, i + 1), "\047")
            if (!j) { bad("an unbalanced quote"); i = n + 1; break }
            t = substr(s, i, j + 1); WR = WR t; WM = WM t; i += j + 1; continue
        }
        if (c == "`") { bad("a backtick"); i++; continue }
        if (c == "$") {
            if (ch(i + 1) == "(") {
                if (ch(i + 2) == "(") { bad("arithmetic"); i += 3; continue }
                subst(); continue
            }
            if (ch(i + 1) == "{") { param(0); continue }
            if (ch(i + 1) == "\047" || ch(i + 1) == "[") { bad("an ansi-c quote or arithmetic"); i += 2; continue }
        }
        if (c == "\"") {
            WR = WR c; WM = WM c; i++; q = 1
            while (i <= n) {
                c = ch(i)
                if (c == "\"") { WR = WR c; WM = WM c; i++; q = 0; break }
                if (c == "\\") { WR = WR substr(s, i, 2); WM = WM substr(s, i, 2); i += 2; continue }
                if (c == "`") { bad("a backtick"); i++; continue }
                if (c == "$" && ch(i + 1) == "(") {
                    if (ch(i + 2) == "(") { bad("arithmetic"); i += 3; continue }
                    subst(); continue
                }
                if (c == "$" && ch(i + 1) == "{") { param(1); continue }
                if (c == "$" && ch(i + 1) == "[") { bad("arithmetic"); i += 2; continue }
                if (c == "\n" && NH > 0) bad("a quote across a heredoc")
                WR = WR c; WM = WM c; i++
            }
            if (q) { bad("an unbalanced quote"); break }
            continue
        }
        WR = WR c; WM = WM c; i++
    }
}
function scan_list(closer,   c, rest, op, j, delim, start) {
    while (i <= n) {
        c = ch(i)
        if (c == " " || c == "\t") { i++; continue }
        if (substr(s, i, 2) == "\\\n") { i += 2; continue }
        if (c == "\n") { emit("p" SEP "nl"); i++; if (NH) read_heredocs(); continue }
        if (c == "#") { while (i <= n && ch(i) != "\n") i++; continue }
        if (c == ")") { i++; if (closer == ")") return 1; bad("a stray paren"); continue }
        if ((c == "<" || c == ">") && ch(i + 1) == "(") {
            start = i; i += 2
            emit("o" SEP c "("); if (!scan_list(")")) bad("an unbalanced substitution"); emit("c")
            emit("w" SEP substr(s, start, i - start) SEP c "(…)")
            continue
        }
        if (c == "(") {
            if (ch(i + 1) == "(") { bad("arithmetic"); i += 2; continue }
            i++; emit("o" SEP "("); if (!scan_list(")")) bad("an unbalanced group"); emit("c"); continue
        }
        rest = substr(s, i, 4)
        if (match(rest, /^(&&|\|\||\|&|;;|;&)/)) { emit("p" SEP substr(rest, 1, RLENGTH)); i += RLENGTH; continue }
        rest = substr(s, i, 12)
        if (match(rest, /^[0-9]*(<<<|<<-|<<|<>|<&|>&|>>|>\||&>>|&>|<|>)/)) {
            op = substr(rest, 1, RLENGTH); i += RLENGTH
            while (ch(i) == " " || ch(i) == "\t") i++
            if (op ~ /<<-?$/) {
                scan_word(); delim = WR
                if (delim == "" || delim ~ /\$/) { bad("a heredoc delimiter"); continue }
                emit("h" SEP "?")
                NH++; HSTRIP[NH] = (op ~ /-$/); HQ[NH] = (delim ~ /[\047"\\]/); HIDX[NH] = NO
                gsub(/[\047"\\]/, "", delim); HDELIM[NH] = delim
                continue
            }
            if (op ~ /[<>]&$/ && match(substr(s, i, 8), /^([0-9]+|-)([ \t\n;&|<>()]|$)/)) {
                j = substr(s, i, 8); sub(/[ \t\n;&|<>()].*$/, "", j)
                emit("d" SEP op SEP j); i += length(j); continue
            }
            scan_word()
            if (WR == "") { bad("a redirection without a target"); continue }
            emit("r" SEP op SEP WR SEP WM)
            continue
        }
        if (c == "|" || c == ";" || c == "&") { emit("p" SEP c); i++; continue }
        start = i
        scan_word()
        if (i == start) { bad("an unexpected character"); i++; continue }
        emit("w" SEP WR SEP WM)
    }
    return (closer == "")
}
{
    s = $0; n = length(s); i = 1; NO = 0; NH = 0
    if (!scan_list("")) bad("an unbalanced command")
    if (NH) bad("a heredoc without a body")
    for (k = 1; k <= NO; k++) printf "%s\036", OUT[k]
}
AWK

AN_DONE=0          # the analysis ran
AN_OK=1            # it understood the whole command
AN_WHY=""          # the first thing it did not understand (for debugging)
LEX_OK=1           # the lexer read every character
TREE_OK=1          # no git, package-manager, or formatter command in the primary tree would ask
TREE_MSG=""        # the message of the first one that would
CFG_OK=1           # every check-config write lands outside the repository
WRAP=0             # a guarded command the hook cannot place: in a runner, or a push it cannot resolve
RUNNERS=' sudo doas command exec builtin eval env nice nohup timeout xargs stdbuf time watch flock setsid chroot bash sh zsh dash ksh '
CFG_NAME=""
SIGNOFF_LINES=()
VN=(); VV=()       # the command's own variables; \001 marks an unknown value
ADDED_P=(); ADDED_OK=()
MKTEMP_DIRS=(); MK_N=0
LN_SEEN=0
AN_WROTE=0         # a command before this point may have written a file
declare -A AN_KIND=()
RE_DOTGIT="(^|[/\"'])\\.git(\$|[/\"'])"
# `$(ls -d <glob> [2>/dev/null] [| tail -1])`, the usual way to find a scratch
# tree by name.
RE_LSGLOB='^"?\$\(ls( +-[1dtr]+)+ +([^][ ;&|<>()`"'"'"'$\\{}]+)( +2>/dev/null)?( *\| *(tail|head) +(-1|-n *1))?\)"?$'

an_fail() { [ -n "$AN_WHY" ] || AN_WHY=$1; AN_OK=0; }

# Physical path of existing directory $1, in AN_P. Cached: a long command
# names the same few directories many times.
declare -A AN_PHYS=()
hone_an_phys() {
    if [ -n "${AN_PHYS[$1]+x}" ]; then AN_P=${AN_PHYS[$1]}; [ -n "$AN_P" ]; return; fi
    AN_P=$(cd "$1" 2>/dev/null && pwd -P) || AN_P=""
    AN_PHYS[$1]=$AN_P
    [ -n "$AN_P" ]
}

# Normalize absolute path $1 into AN_P. Fails on a `..` component: cd reads
# it lexically and git -C physically, and a symlink tells the two apart.
hone_an_norm() {
    local IFS=/ part out=""
    local -a parts
    case $1 in *$'\n'*) return 1 ;; esac
    read -r -a parts <<<"$1"
    for part in "${parts[@]}"; do
        case $part in ''|.) ;; ..) return 1 ;; *) out+="/$part" ;; esac
    done
    AN_P=${out:-/}
}

# $1 resolved against directory $2, in AN_P.
hone_an_resolve() {
    case $1 in
        /*) hone_an_norm "$1" ;;
        *) [ -n "$2" ] || return 1; hone_an_norm "$2/$1" ;;
    esac
}

# A variable's value in AN_V. 0 = known, 1 = unknown, 2 = unset.
hone_an_var() {
    local i
    for ((i = ${#VN[@]} - 1; i >= 0; i--)); do
        [ "${VN[$i]}" = "$1" ] || continue
        [ "${VV[$i]}" = $'\001' ] && return 1
        [[ ${VV[$i]} == $'\002'* ]] && return 1
        AN_V=${VV[$i]}; return 0
    done
    # An unset TMPDIR expands to nothing, so "$TMPDIR/x" is /x.
    case $1 in
        HOME) [ -n "${HOME:-}" ] || return 2; AN_V=$HOME; return 0 ;;
        TMPDIR) AN_V=${TMPDIR:-}; return 0 ;;
    esac
    return 1
}

hone_an_setvar() {
    local i
    for ((i = ${#VN[@]} - 1; i >= 0; i--)); do
        [ "${VN[$i]}" = "$1" ] && { VV[i]=$2; return 0; }
    done
    VN+=("$1"); VV+=("$2")
}

# The value of shell word $1, in AN_E: quotes removed, the command's own
# variables, HOME, TMPDIR, and `${NAME:-literal}` expanded. Fails on
# anything else the shell would expand or split.
# shellcheck disable=SC2016,SC2088,SC1003  # the literal $( ~ and \ are matched
hone_an_expand() {
    local w=$1 out="" q="" c i=0 name rest def rc
    case $w in *'$('*|*'`'*|*'<('*|*'>('*|*$'\n'*) return 1 ;; esac
    case $w in
        '~'|'~/'*) [ -n "${HOME:-}" ] || return 1; w=$HOME${w#\~} ;;
        '~'*) return 1 ;;
    esac
    while [ "$i" -lt "${#w}" ]; do
        c=${w:i:1}
        if [ "$q" = "'" ]; then
            if [ "$c" = "'" ]; then q=""; else out+=$c; fi
            i=$((i + 1)); continue
        fi
        case $c in
            "'") if [ -z "$q" ]; then q="'"; else out+=$c; fi ;;
            '"') if [ "$q" = '"' ]; then q=""; else q='"'; fi ;;
            '\') return 1 ;;
            '$')
                if [ "${w:i+1:1}" = "{" ]; then
                    rest=${w:i+2}
                    [[ $rest == *"}"* ]] || return 1
                    rest=${rest%%\}*}
                    i=$((i + 2 + ${#rest}))
                    name=${rest%%:-*}
                    [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
                    hone_an_var "$name"; rc=$?
                    if [ "$name" != "$rest" ]; then
                        def=${rest#*:-}
                        case $def in *['$`"\\{}']*|*"'"*) return 1 ;; esac
                        if [ "$rc" -eq 2 ] || { [ "$rc" -eq 0 ] && [ -z "$AN_V" ]; }; then AN_V=$def; rc=0; fi
                    fi
                    [ "$rc" -eq 0 ] || return 1
                else
                    name=${w:i+1}; name=${name%%[!A-Za-z0-9_]*}
                    if [ -z "$name" ]; then
                        case ${w:i+1:1} in ''|'"') out+='$'; i=$((i + 1)); continue ;; *) return 1 ;; esac
                    fi
                    [[ $name =~ ^[A-Za-z_] ]] || return 1
                    i=$((i + ${#name}))
                    hone_an_var "$name" || return 1
                fi
                if [ -z "$q" ]; then
                    case $AN_V in ''|*[[:space:]*?[]*) return 1 ;; esac
                fi
                out+=$AN_V ;;
            '*'|'?'|'['|'{'|'}') [ -n "$q" ] || return 1; out+=$c ;;
            *) out+=$c ;;
        esac
        i=$((i + 1))
    done
    [ -z "$q" ] || return 1
    AN_E=$out
}

hone_an_in() { local x k=$1; shift; for x in "$@"; do [ "$x" = "$k" ] && return 0; done; return 1; }

# The kind of tree absolute path $1 lies in, in KIND: primary (this
# repository's primary tree, or anything inside it that git does not call a
# linked worktree), linked (a linked worktree of this repository whose HEAD is
# not the primary branch), or other. Fails when it cannot tell.
hone_an_kind() {
    local p=$1 a k out g c head i
    if [ -e "$p" ] || [ -L "$p" ]; then
        if [ -L "$p" ] || [ ! -d "$p" ]; then
            a=$(readlink -f -- "$p" 2>/dev/null) || return 1
            [ -n "$a" ] || return 1
            [ -d "$a" ] || a=${a%/*}
        else
            a=$p
        fi
    else
        # A path that does not exist yet. This command made it, or it will
        # not exist when git reaches it. A symlink the command creates could
        # point anywhere, so then nothing here is trusted.
        [ "$LN_SEEN" -eq 0 ] || return 1
        for i in "${!ADDED_P[@]}"; do
            [ "${ADDED_P[$i]}" = "$p" ] || continue
            [ "${ADDED_OK[$i]}" = 1 ] || return 1
            KIND=linked; return 0
        done
        a=$p
        while [ ! -e "$a" ]; do a=${a%/*}; [ -n "$a" ] || a=/; done
        [ -d "$a" ] || return 1
    fi
    [ -n "$a" ] || a=/
    hone_an_phys "$a" || return 1
    a=$AN_P
    if [ -n "${AN_KIND[$a]+x}" ]; then
        k=${AN_KIND[$a]}
    else
        k=other
        if out=$(git -C "$a" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null); then
            g=${out%%$'\n'*}; c=${out#*$'\n'}
            hone_an_phys "$g" && g=$AN_P
            hone_an_phys "$c" && c=$AN_P
            if [ -n "$OUR_COMMON" ] && [ "$c" = "$OUR_COMMON" ]; then
                if [ "$g" = "$c" ]; then
                    k=primary
                else
                    head=$(git -C "$a" symbolic-ref -q HEAD 2>/dev/null)
                    if [ -n "$head" ] && [ "$head" = "$PRIMARY_HEAD" ]; then k=primary; else k=linked; fi
                fi
            fi
        fi
        if [ "$k" = other ] && [ -n "$PRIMARY_TOP" ]; then
            case "$a/" in "$PRIMARY_TOP"/*) k=primary ;; esac
        fi
        AN_KIND[$a]=$k
    fi
    # A worktree this command adds into an existing, empty directory.
    for i in "${!ADDED_P[@]}"; do
        [ "${ADDED_P[$i]}" = "$p" ] || continue
        [ "${ADDED_OK[$i]}" = 1 ] || return 1
        [ "$k" = other ] && k=linked
    done
    KIND=$k
}

hone_an_union() {
    local d
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        case $'\n'"$CURSET"$'\n' in *$'\n'"$d"$'\n'*) ;; *) CURSET+=$'\n'"$d" ;; esac
    done <<<"$1"
}

# A cd, an export, or an assignment moves the shell. Inside a pipeline it runs
# in a subshell, and after `||` it may not run.
hone_an_state_ok() {
    case $1 in '|'|'|&') an_fail "a state change in a pipeline"; return 1 ;; esac
    case $2 in '|'|'|&') an_fail "a state change in a pipeline"; return 1 ;; esac
    [ "$LIST_OR" -eq 0 ] || { an_fail "a state change after ||"; return 1; }
}

# shellcheck disable=SC2016  # the literal $(mktemp -d) is matched
hone_an_assign() {
    local name=${1%%=*} val=${1#*=} v
    case $name in
        GIT_*|CDPATH|HOME|PWD|OLDPWD|IFS|PATH|BASH_ENV|ENV|TMPDIR|SHELLOPTS|BASHOPTS)
            an_fail "an assignment to $name"; return ;;
    esac
    if [[ $val =~ $RE_LSGLOB ]] && hone_an_lsglob; then
        hone_an_setvar "$name" "$AN_SET"
        [ "$COND" -eq 1 ] && CONDV+=" $name"
        return
    fi
    case $val in
        '$(mktemp -d)'|'"$(mktemp -d)"')
            if [ -n "$AN_TMP" ]; then
                MK_N=$((MK_N + 1)); v="$AN_TMP/hone-mktemp.$$.$MK_N"; MKTEMP_DIRS+=("$v")
            else
                v=$'\001'; A_CERTAIN=0
            fi ;;
        *'$('*|*'`'*) v=$'\001'; A_CERTAIN=0 ;;
        *) if hone_an_expand "$val"; then v=$AN_E; else v=$'\001'; fi ;;
    esac
    hone_an_setvar "$name" "$v"
    [ "$COND" -eq 1 ] && CONDV+=" $name"
}

# The glob of the RE_LSGLOB match in BASH_REMATCH, expanded here. The
# variable then holds one of the matches, in AN_SET after \002. Only when
# nothing before it wrote a file, every match is a directory, and the value
# is one match: a single one, or one picked by head or tail. With no match
# the value is empty, and a cd to it fails.
# shellcheck disable=SC2088  # the literal ~ is matched
hone_an_lsglob() {
    local pat=${BASH_REMATCH[2]} pick=${BASH_REMATCH[4]} m out=""
    local -a ms
    [ "$AN_WROTE" -eq 0 ] && [[ ${BASH_REMATCH[0]} =~ \ -[1tr]*d ]] || return 1
    case $pat in '~/'*) pat=$HOME/${pat#'~/'} ;; '~'*|*'**'*|*[[:space:]]*) return 1 ;; esac
    case $pat in /*) ;; *) [[ $CURSET != *$'\n'* ]] || return 1; pat=$CURSET/$pat ;; esac
    # dotglob and nocaseglob make the set a superset of what the shell sees.
    mapfile -t ms < <(shopt -s nullglob dotglob nocaseglob; for m in $pat; do printf '%s\n' "$m"; done)
    [ "${#ms[@]}" -ge 1 ] || return 1
    [ "${#ms[@]}" -eq 1 ] || [ -n "$pick" ] || return 1
    for m in "${ms[@]}"; do
        [ -d "$m" ] || return 1
        out+=${out:+$'\n'}$m
    done
    AN_SET=$'\002'$out
}

# True when word $1 is a bare reference to a variable set by hone_an_lsglob.
# Its candidates in AN_SET.
hone_an_setref() {
    local i name
    [[ $1 =~ ^\"?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\"?$ ]] || return 1
    name=${BASH_REMATCH[1]}
    for ((i = ${#VN[@]} - 1; i >= 0; i--)); do
        [ "${VN[$i]}" = "$name" ] || continue
        [[ ${VV[$i]} == $'\002'* ]] || return 1
        AN_SET=${VV[$i]#$'\002'}
        # Unquoted, the shell splits and globs the value.
        [[ $1 == '"'* ]] || ! [[ $AN_SET =~ [[:blank:]*?[] ]]; return
    done
    return 1
}

hone_an_cd() {
    local prev=$1 nx=$2 a=$3 j tgt="" cnt=0 p
    hone_an_state_ok "$prev" "$nx" || return
    [ "$a" -eq 0 ] || { an_fail "an environment prefix on cd"; return; }
    for ((j = a + 1; j < ${#W[@]}; j++)); do
        case ${W[$j]} in -*) an_fail "a cd option"; return ;; esac
        tgt=${W[$j]}; cnt=$((cnt + 1))
    done
    [ "$cnt" -le 1 ] || { an_fail "a cd with two targets"; return; }
    if [ "$cnt" -eq 1 ] && hone_an_setref "$tgt"; then
        local c set=""
        while IFS= read -r c; do
            hone_an_phys "$c" || { an_fail "a cd target that does not resolve"; return; }
            set+=${set:+$'\n'}$AN_P
        done <<<"$AN_SET"
        [ "$COND" -eq 1 ] && ALT+=$'\n'"$CURSET"
        CURSET=$set; CERTAIN=1; return
    fi
    if [ "$cnt" -eq 0 ]; then
        [ -n "${HOME:-}" ] || { an_fail "a cd to an unset HOME"; return; }
        AN_E=$HOME
    elif ! hone_an_expand "$tgt" || [ -z "$AN_E" ]; then
        an_fail "a cd target the hook cannot resolve"; return
    fi
    case $AN_E in
        /*) hone_an_norm "$AN_E" || { an_fail "a cd target with .."; return; } ;;
        *)
            if [ -n "${CDPATH:-}" ] && [[ $AN_E != ./* ]]; then an_fail "a relative cd under CDPATH"; return; fi
            [[ $CURSET != *$'\n'* ]] || { an_fail "a relative cd from an uncertain directory"; return; }
            hone_an_norm "$CURSET/$AN_E" || { an_fail "a cd target with .."; return; } ;;
    esac
    p=$AN_P
    if [ -d "$p" ] && [ -x "$p" ]; then
        hone_an_phys "$p" || { an_fail "a cd target that does not resolve"; return; }
        p=$AN_P; CERTAIN=1
    elif [ "$LN_SEEN" -eq 0 ] && hone_an_in "$p" "${MKTEMP_DIRS[@]+"${MKTEMP_DIRS[@]}"}"; then
        CERTAIN=1
    elif [ "$LN_SEEN" -eq 0 ] && [[ $'\n'"$MADE"$'\n' == *$'\n'"$p"$'\n'* ]]; then
        :
    else
        an_fail "a cd into a directory that does not exist"; return
    fi
    [ "$COND" -eq 1 ] && ALT+=$'\n'"$CURSET"
    CURSET=$p
}

# Parse the git command at word $1: GSUB, GSUBI, and GTD (the tree each
# directory of CURSET reaches through the -C chain). GFAIL says why not.
hone_an_git() {
    local a=$1 j w d t p ts c nts
    local -a cpaths=()
    GSUB=""; GSUBI=-1; GTD=""; GFAIL=""
    for ((j = a + 1; j < ${#W[@]}; j++)); do
        w=${W[$j]}
        case $w in
            -C) j=$((j + 1)); cpaths+=("${W[$j]:-}") ;;
            --no-pager|--no-optional-locks|--no-replace-objects|-P|--paginate) ;;
            -*) GFAIL="the git option $w"; return ;;
            *) hone_an_expand "$w" || { GFAIL="a git subcommand the hook cannot read"; return; }
               GSUB=$AN_E; GSUBI=$j; break ;;
        esac
    done
    while IFS= read -r d; do
        ts=$d
        for p in "${cpaths[@]+"${cpaths[@]}"}"; do
            if hone_an_setref "$p"; then
                c=$AN_SET
            else
                hone_an_expand "$p" && [ -n "$AN_E" ] || { GFAIL="a git -C path the hook cannot resolve"; return; }
                c=$AN_E
            fi
            if [[ $ts$c != *$'\n'* ]]; then
                hone_an_resolve "$c" "$ts" || { GFAIL="a git -C path with .."; return; }
                ts=$AN_P; continue
            fi
            nts=""
            while IFS= read -r t; do
                while IFS= read -r w; do
                    hone_an_resolve "$w" "$t" || { GFAIL="a git -C path with .."; return; }
                    nts+=${nts:+$'\n'}$AN_P
                done <<<"$c"
            done <<<"$ts"
            ts=$nts
        done
        GTD+=${GTD:+$'\n'}$ts
    done <<<"$CURSET"
}

# `git worktree add`: record the path it creates. A detached or new-branch
# worktree is safe to merge in. Any other form, or a path the hook cannot
# resolve, makes every later use of that path unknown.
hone_an_worktree_add() {
    local nx=$1 j w ok=0 bad=0 path="" d
    for ((j = GSUBI + 2; j < ${#W[@]}; j++)); do
        w=${W[$j]}
        case $w in
            --detach|-d) ok=1 ;;
            -b) ok=1; j=$((j + 1)) ;;
            -q|--quiet|--no-checkout|--checkout|--lock|--no-track|--track|--guess-remote|--no-guess-remote) ;;
            --reason) j=$((j + 1)) ;;
            -*) bad=1 ;;
            *) path=$w; break ;;
        esac
    done
    [ -n "$path" ] || return 0
    [ -z "$GFAIL" ] && hone_an_expand "$path" && [ -n "$AN_E" ] \
        || { an_fail "a worktree added at a path the hook cannot resolve"; return; }
    while IFS= read -r d; do
        hone_an_resolve "$AN_E" "$d" || { an_fail "a worktree path with .."; return; }
        ADDED_P+=("$AN_P"); ADDED_OK+=("$(( ok == 1 && bad == 0 ))")
        if [ "$nx" = '&&' ] && [ "$LIST_OR" -eq 0 ]; then MADE+=$'\n'"$AN_P"; fi
    done <<<"$GTD"
}

# `git reset [-q] <path>...` unstages when every operand is a path that
# exists in the tree or the index and names no revision, judged in directory $1.
hone_an_reset_paths() {
    local d=$1 j w n=0
    for ((j = GSUBI + 1; j < ${#W[@]}; j++)); do
        w=${W[$j]}
        case $w in
            -q|--quiet) ;;
            -*) return 1 ;;
            *[~^@:]*) return 1 ;;
            *)
                hone_an_expand "$w" && [ -n "$AN_E" ] || return 1
                case $AN_E in /*) return 1 ;; esac
                [ -e "$d/$AN_E" ] || git -C "$d" ls-files --error-unmatch -- "$AN_E" >/dev/null 2>&1 || return 1
                git -C "$d" rev-parse -q --verify "$AN_E" >/dev/null 2>&1 && return 1
                git -C "$d" rev-parse -q --verify "$AN_E^{commit}" >/dev/null 2>&1 && return 1
                n=$((n + 1)) ;;
        esac
    done
    [ "$n" -ge 1 ]
}

# True when trigger text $1, run in primary-tree directory $2, is a move or
# a write the rules below would ask about. AN_MSG names the rule's message.
hone_an_primary_unsafe() {
    local tt=$1 d=$2 j exp=""
    AN_MSG=msg_bashguard_head_move
    [[ $tt =~ $RE_HEAD ]] && return 0
    [[ $tt =~ $RE_STASH ]] && ! [[ $tt =~ $RE_STASH_READ ]] && return 0
    [[ $tt =~ $RE_CHECKOUT ]] && ! [[ $tt =~ $RE_DASHDASH ]] && return 0
    AN_MSG=msg_bashguard_branch_move
    [[ $tt =~ $RE_MOVER ]] && return 0
    if [[ $tt =~ $RE_RESET ]]; then
        [[ $tt =~ $RE_DASHDASH ]] || [[ $tt =~ $RE_RESET_BARE ]] || hone_an_reset_paths "$d" || return 0
    fi
    AN_MSG=msg_bashguard_self_writer
    [[ $tt =~ $RE_SELF ]] && return 0
    AN_MSG=msg_bashguard_formatter
    if [[ $tt =~ $RE_FMT ]]; then
        [ "$d" = "$PRIMARY_TOP" ] || return 0
        for ((j = AN_A; j < ${#W[@]}; j++)); do
            if hone_an_expand "${W[$j]}"; then exp+=" $AN_E"; else exp+=" ${W[$j]}"; fi
        done
        hone_fmt_scoped "$exp" || return 0
    fi
    return 1
}

# A move or a write in the primary tree. The first one names the message.
hone_an_unsafe() { TREE_OK=0; TREE_MSG=${TREE_MSG:-$AN_MSG}; }

# The leading assignments of the current command (words 0 to $1) change
# nothing a guarded command reads.
hone_an_env_ok() {
    local j
    for ((j = 0; j < $1; j++)); do
        case ${W[$j]%%=*} in
            GIT_EDITOR|GIT_SEQUENCE_EDITOR|GIT_PAGER|GIT_TERMINAL_PROMPT|GIT_AUTHOR_*|GIT_COMMITTER_*|LANG|LC_*|NO_COLOR|FORCE_COLOR|CI|TERM|TZ) ;;
            *) an_fail "an environment prefix on a guarded command"; return 1 ;;
        esac
    done
}

# `git push` at word $1. A push into this repository can move the primary
# branch from any tree, a scratch clone of the primary tree included. So it
# counts as a move in the primary tree. The destination is the repository
# argument, or the remote git picks for the branch, and a remote name stands
# for its push URLs. A URL on another host passes. A push the hook cannot
# resolve asks, as a clone this same command makes could have any origin.
hone_an_push() {
    local j w dest="" d r b urls u
    [ -z "$GFAIL" ] || { an_fail "$GFAIL"; WRAP=1; return; }
    hone_an_env_ok "$1" || return
    for ((j = GSUBI + 1; j < ${#W[@]}; j++)); do
        w=${W[$j]}
        case $w in
            --repo|--repo=*|-o|--push-option|--receive-pack*|--exec*) an_fail "git push $w"; WRAP=1; return ;;
            -*) ;;
            *) hone_an_expand "$w" && [ -n "$AN_E" ] || { an_fail "a push destination the hook cannot read"; WRAP=1; return; }
               dest=$AN_E; break ;;
        esac
    done
    while IFS= read -r d; do
        [ -d "$d" ] || { an_fail "a push from a tree that does not exist yet"; WRAP=1; return; }
        r=$dest
        if [ -z "$r" ]; then
            b=$(git -C "$d" symbolic-ref -q --short HEAD 2>/dev/null)
            r=$(git -C "$d" config "branch.$b.pushRemote" || git -C "$d" config remote.pushDefault \
                || git -C "$d" config "branch.$b.remote") || r=origin
        fi
        urls=$(git -C "$d" remote get-url --push --all "$r" 2>/dev/null) || urls=$r
        while IFS= read -r u; do
            hone_an_push_url "$u" "$d"
        done <<<"$urls"
    done <<<"$GTD"
}

# Push URL $1, read from directory $2: a move when it names this repository.
# shellcheck disable=SC2088  # the literal ~ is matched
hone_an_push_url() {
    local u=${1#file://} p c
    case $1 in file://*) ;; [A-Za-z]*://*) return 0 ;; esac
    # host:path is ssh when no slash comes before the colon.
    case ${u%%/*} in *:*) return 0 ;; esac
    case $u in '~/'*) u=$HOME/${u#'~/'} ;; '~'*) an_fail "a push to another user's home"; return ;; esac
    case $u in /*) ;; *) u=$2/$u ;; esac
    for p in "$u" "$u.git"; do
        [ -d "$p" ] || continue
        c=$(git -C "$p" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
        hone_an_phys "$c" || { an_fail "a push destination that does not resolve"; return; }
        if [ -z "$OUR_COMMON" ] || [ "$AN_P" = "$OUR_COMMON" ]; then
            AN_MSG=msg_bashguard_branch_move; hone_an_unsafe
        fi
        return 0
    done
}

# A check-config path $1 (a raw word) is written: it must land outside the
# repository from every directory the command may run in.
hone_an_cfg_judge() {
    local raw=${1#of=} name d
    name=$(printf '%s\n' "$raw" | grep -Eo "$HONE_CHECK_CONFIG_RE" | tail -n 1)
    if hone_an_expand "$raw" && [ -n "$AN_E" ]; then
        while IFS= read -r d; do
            if ! hone_an_resolve "$AN_E" "$d" || ! hone_an_kind "$AN_P" || [ "$KIND" != other ]; then
                CFG_OK=0; CFG_NAME=${CFG_NAME:-$name}; return
            fi
        done <<<"$CURSET"
        return
    fi
    CFG_OK=0; CFG_NAME=${CFG_NAME:-$name}
}

# True when raw word $1 names a check config.
hone_an_is_cfg() {
    [[ $1 =~ $CFG ]] && return 0
    hone_an_expand "$1" && [[ $AN_E =~ $CFG ]]
}

# The redirections of the current command: sign-off text and config writes.
hone_an_redirs() {
    local k
    for k in "${!RD[@]}"; do
        case ${RDOP[$k]} in
            *'<<<') ;;
            *'>'*) hone_an_is_cfg "${RD[$k]}" && hone_an_cfg_judge "${RD[$k]}" ;;
        esac
    done
}

# One simple command: W and WM (its words), RDOP/RD (its redirections), HB/HQ
# (its heredoc bodies). $1 and $2 are the operators before and after it.
hone_an_simple() {
    local prev=$1 nx=$2 n=${#W[@]} a=0 j k w cw="" base="" tt="" line="" skip=0 d t
    local mdrop=0 dataok=0
    # Leading assignments.
    while [ "$a" -lt "$n" ] && [[ ${W[$a]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do a=$((a + 1)); done
    AN_A=$a
    if [ "$a" -lt "$n" ]; then
        if [[ ${W[$a]} == *'$'* ]] || ! hone_an_expand "${W[$a]}" || [ -z "$AN_E" ]; then
            an_fail "a command word the hook cannot read"
        else
            cw=$AN_E; base=${cw##*/}
        fi
    fi
    if [ "$base" = git ]; then
        hone_an_git "$a"
        case $GSUB in commit|tag|merge|notes|stash) mdrop=1 ;; esac
    fi
    # The text the rules read: the words, a git message value dropped, and
    # any here-string. The sign-off line keeps each redirection, and an echo
    # or printf keeps a substitution masked, because its body is read apart.
    for ((j = 0; j < n; j++)); do
        w=${W[$j]}
        if [ "$skip" -eq 1 ]; then skip=0; tt+=" ''"; line+=" ''"; continue; fi
        if [ "$mdrop" -eq 1 ] && [ "$j" -gt "$GSUBI" ]; then
            case $w in
                -m|--message|-[A-Za-z]*m) skip=1 ;;
                --message=*|-m?*) w="-m''" ;;
            esac
        fi
        [ "$j" -ge "$a" ] && tt+=" $w"
        case $base in echo|printf) line+=" ${WM[$j]}" ;; *) line+=" $w" ;; esac
        [[ $w =~ $RE_DOTGIT ]] && an_fail "a word that names a .git path"
    done
    for k in "${!RD[@]}"; do
        line+=" ${RDOP[$k]}${RD[$k]}"
        case ${RDOP[$k]} in *'<<<') tt+=" ${RD[$k]}" ;; esac
        [[ ${RD[$k]} =~ $RE_DOTGIT ]] && an_fail "a redirection into a .git path"
    done
    SIGNOFF_LINES+=("$line")
    tt=${tt# }

    # Heredoc bodies. Their lines count as sign-off text. A commit message
    # read from stdin is data. Any other body that names a rule's command is
    # a script the hook does not read.
    if [ "${#HB[@]}" -gt 0 ]; then
        if [ "$base" = git ]; then
            case $GSUB in commit|tag|notes)
                for ((j = GSUBI + 1; j < n; j++)); do
                    case ${W[$j]} in -F|--file) [ "${W[$j+1]:-}" = - ] && dataok=1 ;; -F-|--file=-) dataok=1 ;; esac
                done ;;
            esac
        fi
        for k in "${!HB[@]}"; do
            while IFS= read -r w; do SIGNOFF_LINES+=("$w"); done <<<"${HB[$k]}"
            # shellcheck disable=SC2016  # a literal $( in the body
            if [ "${HQ[$k]}" != 1 ] && [[ ${HB[$k]} == *'$('* || ${HB[$k]} == *'`'* ]]; then
                an_fail "a heredoc body with a substitution"
            fi
            [ "$dataok" -eq 1 ] && continue
            if hone_an_triggers "${HB[$k]}" || [[ ${HB[$k]} =~ $RE_CFG_REDIR || ${HB[$k]} =~ $RE_CFG_VERB ]]; then
                an_fail "a heredoc body that names a guarded command"
                [[ $RUNNERS == *" $base "* ]] && WRAP=1
            fi
        done
    fi

    hone_an_redirs
    case $base in ''|cd|export|ls|tail|head|pwd|echo|printf|true|:|test|'[') ;; *) AN_WROTE=1 ;; esac
    for k in "${!RD[@]}"; do
        case ${RDOP[$k]} in *'>'*) [ "${RD[$k]}" = /dev/null ] || AN_WROTE=1 ;; esac
    done

    if [ "$a" -eq "$n" ]; then
        [ "$n" -gt 0 ] || return 0
        hone_an_state_ok "$prev" "$nx" || return 0
        A_CERTAIN=1
        for ((j = 0; j < n; j++)); do hone_an_assign "${W[$j]}"; done
        CERTAIN=$A_CERTAIN
        return 0
    fi
    [ -n "$cw" ] || return 0

    case $cw in
        cd) hone_an_cd "$prev" "$nx" "$a"; return 0 ;;
        export)
            hone_an_state_ok "$prev" "$nx" || return 0
            for ((j = a + 1; j < n; j++)); do
                case ${W[$j]} in
                    -*) an_fail "an export option"; return 0 ;;
                    *=*) [[ ${W[$j]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || { an_fail "an export the hook cannot read"; return 0; }
                         A_CERTAIN=1; hone_an_assign "${W[$j]}" ;;
                    GIT_*|CDPATH|PATH|HOME|TMPDIR) an_fail "an export of ${W[$j]}"; return 0 ;;
                esac
            done
            return 0 ;;
        true|:) CERTAIN=1 ;;
        pushd|popd|eval|source|.|exec|builtin|command|alias|unalias|trap|shopt|set|enable|hash|unset|declare|typeset|local|readonly|let|read|mapfile|readarray|getopts|'if'|'then'|'elif'|'else'|'fi'|'for'|'while'|'until'|'do'|'done'|'case'|'esac'|'select'|'function'|'time'|'coproc'|'{'|'}'|'!'|'[['|']]'|'in')
            an_fail "the shell construct $cw"
            [[ $RUNNERS == *" $cw "* ]] && hone_an_triggers "$tt" && WRAP=1
            return 0 ;;
        printf) for ((j = a + 1; j < n; j++)); do [[ ${W[$j]} == -v* ]] && an_fail "printf -v"; done ;;
        ln) LN_SEEN=1 ;;
        cp) for ((j = a + 1; j < n; j++)); do [[ ${W[$j]} =~ ^(-[A-Za-z]*s|--symbolic-link)$ ]] && LN_SEEN=1; done ;;
    esac
    [ "$base" = git ] && [ "$GSUB" = worktree ] && [ "${W[$GSUBI+1]:-}" = add ] && hone_an_worktree_add "$nx"
    [ "$base" = git ] && [ "$GSUB" = worktree ] && case ${W[$GSUBI+1]:-} in add|list|prune|remove) ;; *) an_fail "a git worktree subcommand" ;; esac

    # Check-config writes by a verb.
    case $base in
        tee|rm|chmod|chattr|truncate)
            for ((j = a + 1; j < n; j++)); do
                [[ ${W[$j]} == -* ]] && continue
                hone_an_is_cfg "${W[$j]}" && hone_an_cfg_judge "${W[$j]}"
            done ;;
        sed)
            if [[ " ${W[*]:a} " =~ [[:space:]](-i|--in-place)[^[:space:]]*[[:space:]] ]] \
               || [[ " ${W[*]:a} " =~ [[:space:]]-[A-Za-z]*i[A-Za-z]*[[:space:]] ]]; then
                for ((j = a + 1; j < n; j++)); do
                    hone_an_is_cfg "${W[$j]}" && hone_an_cfg_judge "${W[$j]}"
                done
            fi ;;
        cp|mv|install|ln)
            t=0
            for ((j = a + 1; j < n; j++)); do
                case ${W[$j]} in -t|--target-directory*|-t?*) an_fail "a target-directory option" ;; esac
                [[ ${W[$j]} == -* ]] && continue
                hone_an_is_cfg "${W[$j]}" && t=1
                [ "$base" = mv ] && hone_an_is_cfg "${W[$j]}" && hone_an_cfg_judge "${W[$j]}"
            done
            [ "$t" -eq 1 ] && hone_an_cfg_judge "${W[$n-1]}" ;;
        dd)
            for ((j = a + 1; j < n; j++)); do
                [[ ${W[$j]} == of=* ]] && hone_an_is_cfg "${W[$j]#of=}" && hone_an_cfg_judge "${W[$j]}"
            done ;;
        echo|printf) ;;
        *)
            # A config write spelled inside another command's text.
            if [[ $tt =~ $RE_CFG_REDIR || $tt =~ $RE_CFG_VERB ]]; then
                an_fail "a config write inside the text of $base"
            fi ;;
    esac

    if [ "$base" = git ] && [ "$GSUB" = push ]; then hone_an_push "$a"; return 0; fi

    # The primary-tree rules.
    hone_an_triggers "$tt" || return 0
    hone_an_env_ok "$a" || return 0
    case $base in
        git)
            [ -z "$GFAIL" ] || { an_fail "$GFAIL"; return 0; }
            case $GSUB in bisect|submodule|filter-branch|filter-repo) an_fail "git $GSUB"; return 0 ;; esac
            for ((j = GSUBI + 1; j < n; j++)); do
                case ${W[$j]} in --exec|--exec=*|-x|--ignore-other-worktrees) an_fail "git ${W[$j]}"; return 0 ;; esac
            done
            while IFS= read -r d; do
                hone_an_kind "$d" || { an_fail "a tree the hook cannot tell"; return 0; }
                case $KIND in
                    primary) hone_an_primary_unsafe "$tt" "$d" && hone_an_unsafe ;;
                    linked) [[ $tt =~ $RE_REF_MOVER ]] && { an_fail "a ref move in a worktree that shares the refs"; return 0; } ;;
                esac
            done <<<"$GTD" ;;
        npm|pnpm|yarn|bun|bunx|npx|pnpx|deno|pip|pip3|uv|uvx|poetry|cargo|bundle|gem|mix|composer|go|biome|eslint|prettier|dprint|ruff|black|isort|rustfmt|gofmt|jscodeshift|codemod)
            while IFS= read -r d; do
                hone_an_kind "$d" || { an_fail "a tree the hook cannot tell"; return 0; }
                if [ "$KIND" = primary ]; then
                    hone_an_primary_unsafe "$tt" "$d" && hone_an_unsafe
                    continue
                fi
                # Outside the primary tree, the tool must not reach back in.
                for ((j = a + 1; j < n; j++)); do
                    w=${W[$j]}
                    case $w in
                        -C|-t|--cwd*|--prefix*|--dir|--dir=*|--directory*|--manifest-path*|--project*|--root*|--target*|--global-dir*|--modules-folder*)
                            an_fail "a tool option that names a directory"; return 0 ;;
                    esac
                    if hone_an_expand "$w"; then w=$AN_E; elif [[ $w == *'$'* ]]; then an_fail "a tool argument the hook cannot read"; return 0; fi
                    case $w in /*|'~'*|*..*) an_fail "a tool argument outside its directory"; return 0 ;; esac
                done
            done <<<"$CURSET" ;;
        *) an_fail "a guarded command named inside $base"
           [[ $RUNNERS == *" $base "* ]] && WRAP=1 ;;
    esac
}

# True when text $1 names a command one of the primary-tree rules reads.
hone_an_triggers() {
    [[ $1 =~ $RE_HEAD || $1 =~ $RE_STASH || $1 =~ $RE_CHECKOUT || $1 =~ $RE_MOVER \
       || $1 =~ $RE_RESET || $1 =~ $RE_SELF || $1 =~ $RE_FMT ]]
}

hone_an_end_cmd() {
    local nx=$1
    if [ "${#W[@]}" -eq 0 ] && [ "${#RD[@]}" -eq 0 ] && [ "${#HB[@]}" -eq 0 ] && [ "$GROUP" -eq 0 ]; then
        case $nx in '&&'|'||'|'|'|'|&') an_fail "an operator with no command before it" ;; esac
        return 0
    fi
    CERTAIN=0
    if [ "$GROUP" -eq 1 ]; then
        [ "${#W[@]}" -eq 0 ] || an_fail "words after a group"
        local line="" k
        for k in "${!RD[@]}"; do line+=" ${RDOP[$k]}${RD[$k]}"; done
        SIGNOFF_LINES+=("$line")
        hone_an_redirs
        [ "${#RD[@]}" -eq 0 ] || AN_WROTE=1
    else
        hone_an_simple "$PREV" "$nx"
    fi
    [ "$CERTAIN" -eq 1 ] || COND=1
    W=(); WM=(); RDOP=(); RD=(); RDM=(); HB=(); HQ=(); GROUP=0
}

hone_an_end_list() {
    local v
    hone_an_union "$ALT"; ALT=""
    for v in $CONDV; do hone_an_setvar "$v" $'\001'; done
    CONDV=""; MADE=""; LIST_OR=0; COND=0
}

# One list: the records from AP up to the group's close. A group or a
# substitution is a nested call, so its cd and its variables end with it.
hone_an_walk() {
    local -a VN=("${VN[@]+"${VN[@]}"}") VV=("${VV[@]+"${VV[@]}"}")
    local CURSET=$CURSET MADE="" ALT="" CONDV="" LIST_OR=0 COND=0 PREV=start GROUP=0
    local -a W=() WM=() RDOP=() RD=() RDM=() HB=() HQ=()
    local rec k rest
    while [ "$AP" -lt "$AN" ]; do
        rec=${AR[$AP]}; AP=$((AP + 1))
        k=${rec%%$'\037'*}; rest=${rec#*$'\037'}
        case $k in
            w) W+=("${rest%%$'\037'*}"); WM+=("${rest#*$'\037'}") ;;
            r) RDOP+=("${rest%%$'\037'*}"); rest=${rest#*$'\037'}
               RD+=("${rest%%$'\037'*}"); RDM+=("${rest#*$'\037'}") ;;
            d) ;;
            h) HQ+=("${rest%%$'\037'*}"); HB+=("${rest#*$'\037'}") ;;
            x) LEX_OK=0; an_fail "$rest" ;;
            o)
                if [ "$rest" = "(" ]; then
                    [ "${#W[@]}" -eq 0 ] && [ "$GROUP" -eq 0 ] || an_fail "a function or a group after a word"
                    hone_an_walk; GROUP=1
                else
                    hone_an_walk
                fi ;;
            c) hone_an_end_cmd end; hone_an_end_list; return 0 ;;
            p)
                hone_an_end_cmd "$rest"
                case $rest in
                    ';'|nl) hone_an_end_list ;;
                    '&&') ;;
                    '||')
                        hone_an_union "$ALT"; ALT=""
                        for k in $CONDV; do hone_an_setvar "$k" $'\001'; done
                        CONDV=""; MADE=""; LIST_OR=1; COND=1 ;;
                    '|'|'|&') ;;
                    *) an_fail "the operator $rest" ;;
                esac
                PREV=$rest ;;
        esac
    done
    hone_an_end_cmd end; hone_an_end_list
}

hone_analyze() {
    [ "$AN_DONE" -eq 0 ] || return 0
    AN_DONE=1
    local out
    OUR_COMMON=""; PRIMARY_TOP=""; PRIMARY_HEAD=""
    if out=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && hone_an_phys "$out"; then
        OUR_COMMON=$AN_P
        out=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
        if [ -n "$out" ] && hone_an_phys "$out"; then
            PRIMARY_TOP=$AN_P
            PRIMARY_HEAD=$(git -C "$PRIMARY_TOP" symbolic-ref -q HEAD 2>/dev/null)
        else
            an_fail "no primary tree"
        fi
    elif hone_an_phys "$PROJECT_ROOT"; then
        PRIMARY_TOP=$AN_P
    fi
    AN_TMP=""
    hone_an_phys "${TMPDIR:-/tmp}" && AN_TMP=$AN_P
    CURSET=""
    hone_an_phys "$SHELL_CWD" && CURSET=$AN_P
    [ -n "$CURSET" ] || { an_fail "no shell directory"; CURSET=/nonexistent; }
    mapfile -d $'\036' -t AR < <(printf '%s' "$ORIG_CMD" | awk "$HONE_LEX_AWK")
    AN=${#AR[@]}; AP=0
    hone_an_walk
}

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
# The deny reads each simple command on its own when the analysis can split
# the command. A substitution inside an echo or printf is read as its own
# command, so a read of .hone-grant/ inside `$(...)` is not the write of the
# echo around it. The write itself is still denied.
SIGNOFF_RE1='(touch|install|printf|echo|tee|cp|mv|mkdir|ln|sed -i|rm |truncate|dd|chmod|chattr)[^|;&]*\.hone-(grant|proof)/'
SIGNOFF_RE2='>>?[[:space:]]*"?'"'"'?[^[:space:]|;&]*\.hone-(grant|proof)/'
if echo "$CMD" | grep -Eq -e "$SIGNOFF_RE1" -e "$SIGNOFF_RE2"; then
    hone_analyze
    if [ "$LEX_OK" -eq 0 ] \
       || printf '%s\n' "${SIGNOFF_LINES[@]+"${SIGNOFF_LINES[@]}"}" | grep -Eq -e "$SIGNOFF_RE1" -e "$SIGNOFF_RE2"; then
        decision deny "$(msg_bashguard_signoff)"
    fi
fi

# 1c. The proof sign-off and the authority grant are the human's acts, so
# `worktree.sh attest` and `grant` stay denied to the agent whatever text
# follows them. The run runs the check or reads the diff, then stops and hands
# the human the command. An agent that may grant itself did so every time in
# the field, and the gate stopped nothing. The sed above already stripped the
# free text, so this matches the invocation alone, never a mention inside a
# message.
if echo "$CMD" | grep -Eq 'worktree\.sh"?[[:space:]]+attest([[:space:]]|$)'; then
    decision deny "$(msg_bashguard_attest)"
fi
if echo "$CMD" | grep -Eq 'worktree\.sh"?[[:space:]]+grant([[:space:]]|$)'; then
    decision deny "$(msg_bashguard_grant)"
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
# The check configs are in the set for the same reason (HONE_CHECK_CONFIG_RE in
# common.sh, shared with guard.sh rule 1b). The gate's test, lint, format, and
# type-check runs are only as strict as the config they read, so an edit there
# turns a red check green without touching the code. The alternation matches
# the basename with no left boundary, like the entries before it, so a nested
# config in a monorepo counts, and a redirect or verb aimed at one asks in any
# The two constructs need different shapes, so they get one branch each.
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
# Each ask names the file. A person approved an unnamed ask without knowing
# which file it meant, and one tracked config was overwritten.
hit=$(printf '%s\n' "$CMD" | grep -Eo -e "${REDIR_PRE}(${PROT})" -e "${VERB_PRE}(${PROT})" | head -n 1)
if [ -n "$hit" ]; then
    decision ask "$(msg_bashguard_protected "$(printf '%s\n' "$hit" | grep -Eo "(${PROT})" | tail -n 1)")"
fi

# 2b. A check config asks in any tree of this repository, and passes outside
# it. A scratch config for a one-off run, such as a mutation check, belongs
# outside the repository, where no gate reads it. The ask fired on such a
# config wherever it went, and unattended runs stalled on it for hours. The
# analysis resolves each written config path in the directory its command
# runs in, $TMPDIR and a `$(mktemp -d)` directory included.
hit=$(printf '%s\n' "$CMD" | grep -Eo -e "$RE_CFG_REDIR" -e "$RE_CFG_VERB" | head -n 1)
if [ -n "$hit" ]; then
    hone_analyze
    if [ "$AN_OK" -eq 0 ] || [ "$CFG_OK" -eq 0 ]; then
        name=$CFG_NAME
        [ -n "$name" ] || name=$(printf '%s\n' "$hit" | grep -Eo "$HONE_CHECK_CONFIG_RE" | tail -n 1)
        decision ask "$(msg_bashguard_check_config "$name")"
    fi
fi

# Rules 3 and 4 both apply to the primary tree alone. They need the tree the
# command WRITES IN, which is not the tree the hook stands in. The hook process
# starts in the directory the session started in, and it stays there for the
# whole session. The shell that runs the command does not. `cd "$WT"` moves that
# shell, and every later Bash call runs in the worktree while the hook still
# stands in the primary tree.
#
# The harness reports the shell's directory in the top-level `cwd` field of the
# hook input. Claude Code updates that field after each `cd`, and when Claude
# enters a worktree, while ${CLAUDE_PROJECT_DIR} and the hook's own cwd stay
# put. Reading it is the whole fix for the common misfire: the run loop cds into
# its worktree once (skills/run/SKILL.md step 1) and works there, so every
# formatter run and every package install after that cd read as primary-tree
# work. Rule 4 then told the agent to move work into a worktree it was already
# standing in.
#
# Fall back to the hook's own cwd when the field is absent or names no directory
# (an older harness, a hand-driven test).
# (SHELL_CWD is read above, because the analysis needs it too.)

# A leading `cd <target>` moves the shell once more, inside the command itself,
# so it wins over the field above. A relative target resolves against the
# shell's directory, not the hook's.
#
# Fail closed on anything unclear, which keeps the escalation rather than
# dropping it. Unclear means more than one cd, a cd that is not first, or a
# target that is not a directory. A command that returns to the primary tree
# must never read as worktree work. Each case falls back to the shell's cwd.
#
# A subshell wraps the same idiom: `(cd <worktree> && <tool>)`. The `(` counts
# as a separator here, and the extractor accepts one before a leading cd.
# Without that, the wrapped form read as primary-tree work while the unwrapped
# form passed, and the hook told the agent to move work it had already moved.
TREE_DIR="$SHELL_CWD"
if [ "$(printf '%s\n' "$CMD" | grep -Eo '(^|[;&|(][[:space:]]*)cd[[:space:]]' | wc -l)" -eq 1 ]; then
    CD_TARGET=$(printf '%s' "$CMD" | sed -n \
        "s/^[[:space:]]*(\{0,1\}[[:space:]]*cd[[:space:]]\{1,\}\(\"[^\"]*\"\|'[^']*'\|[^[:space:];&|]\{1,\}\).*/\1/p")
    CD_TARGET=${CD_TARGET%\"}; CD_TARGET=${CD_TARGET#\"}
    CD_TARGET=${CD_TARGET%\'}; CD_TARGET=${CD_TARGET#\'}
    case "$CD_TARGET" in
        ''|/*) ;;
        *) CD_TARGET="$SHELL_CWD/$CD_TARGET" ;;
    esac
    [ -n "$CD_TARGET" ] && [ -d "$CD_TARGET" ] && TREE_DIR="$CD_TARGET"
fi

# git-dir == common-dir ⇔ TREE_DIR is the primary tree, not a linked worktree
# (whose git-dir sits under .git/worktrees/). So neither rule fires for work
# aimed at a worktree, which is where both operations are safe and belong.
# Both paths are absolute: in a subdirectory git prints the one absolute and
# the other relative, and the primary tree's subdirectories passed.
hone_is_primary_tree() {
    [ -d "$1" ] || return 1
    [ "$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null)" \
      = "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ]
}

IN_PRIMARY_TREE=0
hone_is_primary_tree "$TREE_DIR" && IN_PRIMARY_TREE=1

# The resolution above reads ONE leading cd, which is the shape the loop uses.
# Every other way a command names a tree fell back to the shell's directory,
# and that fallback only fails closed while the shell already stands in the
# primary tree. The command that merged around the loop in the ImpossibleBench
# probe had the other shape: the shell stood in a worktree, and the command cd'd
# BACK to the primary tree to merge there. So read every tree the command names
# as well: a later cd, `git -C <path>`, and `--git-dir=<path>`. Any of them in
# the primary tree makes this primary-tree work.
#
# This only ever adds an escalation. A command that names no tree but the one
# the leading cd already resolved is judged exactly as before, so the loop's
# `cd <worktree>` and the subshell form still pass.
if [ "$IN_PRIMARY_TREE" -eq 0 ]; then
    while IFS= read -r _t; do
        [ -n "$_t" ] || continue
        _t=${_t%\"}; _t=${_t#\"}; _t=${_t%\'}; _t=${_t#\'}
        # --git-dir names the repository directory, so its tree is the parent.
        case "$_t" in */.git) _t=${_t%/.git} ;; .git) _t=. ;; esac
        case "$_t" in /*) ;; *) _t="$SHELL_CWD/$_t" ;; esac
        hone_is_primary_tree "$_t" && { IN_PRIMARY_TREE=1; break; }
    done < <(printf '%s\n' "$CMD" \
        | grep -Eo -e '(^|[;&|(][[:space:]]*)cd[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|]+)' \
                   -e '(^|[[:space:]])-C[[:space:]]+("[^"]*"|[^[:space:];&|]+)' \
                   -e '(^|[[:space:]])--git-dir[=[:space:]]("[^"]*"|[^[:space:];&|]+)' \
        | sed -E 's/^[^A-Za-z-]*//; s/^(cd|-C|--git-dir)[=[:space:]]+//')
fi

# Every rule from here on asks through primary_ask. It first asks the
# analysis above. When the analysis understands the whole command and finds
# no primary-tree move or write in it, the command passes, and no later rule
# needs to read it. Otherwise the rule's own ask stands.
primary_ask() {
    hone_analyze
    [ "$AN_OK" -eq 1 ] && [ "$TREE_OK" -eq 1 ] && exit 0
    decision ask "$($1)"
}
# 3. A HEAD-moving git op in the PRIMARY tree → ask. The primary tree is a merge
# target kept on the trunk. Landing goes through `worktree.sh land`, which
# serializes the merge under a lock. Moving the shared HEAD by hand (a branch
# switch, a stash, a hard reset) races every other session that shares this
# tree. That is the exact collision this rule guards against. Investigation
# belongs in a throwaway `git worktree add --detach`. `git checkout` has its own rule below, because
# one of its forms restores files and moves no HEAD.
if [ "$IN_PRIMARY_TREE" -eq 1 ] \
   && echo "$CMD" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+(switch([[:space:]]|$)|reset[^|;&]*--(hard|merge|keep))'; then
    primary_ask msg_bashguard_head_move
fi

# 3a. `git stash` reads in two of its forms and mutates in every other. `list`
# and `show` only read the stash, and the rule used to escalate them with the
# rest. That ask stopped unattended runs on a read, and one agent paged the
# operator to confirm a `git stash list`. So the two read verbs pass, judged
# per segment the way rule 3b judges checkout. Everything else still asks:
# `pop`, `drop`, `clear`, a bare `git stash`, a flags-first form like
# `git stash -u`, and any subcommand this rule does not know. Unknown fails
# closed, so a new stash verb escalates until someone reads it.
if [ "$IN_PRIMARY_TREE" -eq 1 ]; then
    while IFS= read -r seg; do
        printf '%s\n' "$seg" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+stash([[:space:]]|$)' || continue
        printf '%s\n' "$seg" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+stash[[:space:]]+(list|show)([[:space:]]|$)' && continue
        primary_ask msg_bashguard_head_move
    done < <(printf '%s\n' "$CMD" | tr '|;&' '\n\n\n')
fi

# 3b. `git checkout` moves HEAD in one form and restores files in another, so it
# needs the extra check that rule 3 does not. `git checkout -- <paths>` and `git
# checkout <ref> -- <paths>` write files and leave HEAD where it is, which is
# the sanctioned way to undo a bad edit in the primary tree. Flagging them sent
# the operator to a scratch worktree to restore two files.
#
# The `--` pathspec separator is the signal. The rule reads it per command
# segment, so a restore later in the line cannot excuse a real HEAD move
# earlier in it.
# Residual false positive: `git checkout <file>` without the separator is
# indistinguishable from `git checkout <branch>` here, so it still asks.
if [ "$IN_PRIMARY_TREE" -eq 1 ]; then
    while IFS= read -r seg; do
        printf '%s\n' "$seg" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+checkout([[:space:]]|$)' || continue
        printf '%s\n' "$seg" | grep -Eq '[[:space:]]--([[:space:]]|$)' && continue
        primary_ask msg_bashguard_head_move
    done < <(printf '%s\n' "$CMD" | tr '|;&' '\n\n\n')
fi

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
# accepts the global options that take their argument separately, which is how
# `git -C <primary tree> merge` reaches the branch from a worktree shell. It
# accepts no other token, so `git log --grep=merge x` never reads as a merge.
#
# Here `git push` counts only when its remote is a local path, and rule 5
# judges a push by the repository it writes to. Pushing the change branch to
# the team's remote is the loop's own step, and shared-mode land makes the
# primary-branch push itself, inside the lock.
# (GIT_PRE and BRANCH_MOVERS are defined above, with the other patterns.)
if [ "$IN_PRIMARY_TREE" -eq 1 ] \
   && echo "$CMD" | grep -Eq "(^|[^A-Za-z_])${GIT_PRE}(${BRANCH_MOVERS})"; then
    primary_ask msg_bashguard_branch_move
fi

# 3d. `git reset` moves the primary branch in every form but two. Rule 3 above
# escalates --hard, --merge, and --keep, whose danger is the working tree.
# --soft and --mixed move the branch and leave the tree alone, and they passed
# in silence. The two that move nothing are a bare `git reset` and a restore
# with the `--` pathspec separator, which unstage. Everything else asks, judged
# per segment the way rules 3a and 3b judge theirs.
if [ "$IN_PRIMARY_TREE" -eq 1 ]; then
    while IFS= read -r seg; do
        printf '%s\n' "$seg" | grep -Eq "(^|[^A-Za-z_])${GIT_PRE}reset([[:space:]]|$)" || continue
        printf '%s\n' "$seg" | grep -Eq '[[:space:]]--([[:space:]]|$)' && continue
        printf '%s\n' "$seg" | grep -Eq "(^|[^A-Za-z_])${GIT_PRE}reset[[:space:]]*$" && continue
        primary_ask msg_bashguard_branch_move
    done < <(printf '%s\n' "$CMD" | tr '|;&' '\n\n\n')
fi

# 4. A tool that writes its OWN files, run in the PRIMARY tree → ask. This is
# the preventive half of the primary-tree rule for the shell route, and
# dirty-guard.sh (afterwards) is the half that catches what this list misses.
# Rule 2 above cannot see these. A package manager rewrites package.json from
# inside its own process, so the command text carries neither a write construct
# nor the path.
#
# This is an allow-list of names, so it DRIFTS by construction. A new package
# manager, a new migrate subcommand, or a wrapper script that calls one is a
# hole until someone adds it here. That is why it only escalates, and why
# dirty-guard checks the effect instead. Keep the boundary loose: a writer
# anywhere in the command, so `bunx biome migrate` and `sudo npm install` both
# match. Accept that prose quoting one of these names also escalates. An
# ask costs one keystroke, and a missed dependency sweep costs a bad commit.
#
# A BARE SYNC INSTALL is the exception: `bun install`, `npm ci`, `poetry
# install`, with flags only, installs what the lockfile already says and writes
# no durable file. It is also the sanctioned next step after a land that changed
# the lockfile, and this rule used to escalate it. dirty-guard sees whatever
# such a command changes. That check catches any write to a durable path,
# so a preventive ask here gains nothing.
#
# The verb's argument separates the two cases. End of command or flag tokens
# only means sync. A non-flag argument names a package, which mutates the
# manifest. So `npm install lodash`, `bun add x`, and `poetry add y` still
# escalate, as does every add/remove/update/upgrade/link verb below.
# (NAMED_ARG and SELF_WRITERS are defined above.)
if [ "$IN_PRIMARY_TREE" -eq 1 ] && echo "$CMD" | grep -Eq "(^|[^A-Za-z0-9_.-])(${SELF_WRITERS})"; then
    primary_ask msg_bashguard_self_writer
fi

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
# (FMT_WRITERS and hone_fmt_scoped are defined above.)

if [ "$IN_PRIMARY_TREE" -eq 1 ]; then
    while IFS= read -r seg; do
        printf '%s\n' "$seg" | grep -Eq "(^|[^A-Za-z0-9_.-])(${FMT_WRITERS})" || continue
        hone_fmt_scoped "$seg" && continue
        primary_ask msg_bashguard_formatter
    done < <(printf '%s\n' "$CMD" | tr '|;&' '\n\n\n')
fi

# 5. A move the rules above did not see. They read the tree from one leading
# cd and from literal -C paths, so a move in the primary tree passed when it
# sat after a subshell's cd, behind a variable, behind `sudo` or `command`,
# or in a push from a scratch clone whose origin is the primary tree. So a
# command that names a guarded command, or any push, gets the analysis too.
# It asks when the analysis finds a move in the primary tree, even in a
# command it does not model in full, when a runner such as `sudo`, `env`,
# or `bash -c` hides the tree of a guarded command, and on a push it cannot
# resolve.
#
# It does not ask on every command the analysis gives up on. In a replay of
# real commands, most such asks were false: a push to the team's remote
# inside a loop, a script whose text names a checkout. See
# docs/spikes/2026-09-26-bash-guard-holes-replay.md.
if hone_an_triggers "$CMD" || [[ $CMD =~ $RE_PUSH ]]; then
    hone_analyze
    if [ "$WRAP" -eq 1 ] || [ "$TREE_OK" -eq 0 ]; then
        msg=$TREE_MSG
        if [ -z "$msg" ]; then
            if [[ $CMD =~ $RE_HEAD || $CMD =~ $RE_STASH || $CMD =~ $RE_CHECKOUT ]]; then msg=msg_bashguard_head_move
            elif [[ $CMD =~ $RE_MOVER || $CMD =~ $RE_RESET || $CMD =~ $RE_PUSH ]]; then msg=msg_bashguard_branch_move
            elif [[ $CMD =~ $RE_SELF ]]; then msg=msg_bashguard_self_writer
            else msg=msg_bashguard_formatter
            fi
        fi
        decision ask "$($msg)"
    fi
fi

exit 0
