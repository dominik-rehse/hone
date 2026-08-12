#!/bin/bash
# Check the shape of hone's message templates. hooks/messages.sh --raw prints
# every template with its kind, and a message the reader can act on holds to a
# fixed form:
#
#   line 1  what happened, ending in a period
#   line 2  Do: one command or one concrete action
#   line 3  Why: ten words or fewer (human-facing only; an agent-facing reason
#           may run longer, since it steers the model)
#
# A paste block (indented two spaces) may follow, so at most four lines come
# before one. Templates of kind `plain` (a receipt, a usage line, one row of a
# status listing) carry no such shape and are skipped.
# Run: bash test/messages_shape.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)

checked=0; fail=0
bad() { fail=$((fail+1)); printf '  FAIL %s: %s\n' "$1" "$2"; }

fn=""; kind=""
declare -a lines=()

check() {
    [ -n "$fn" ] || return 0
    local n=${#lines[@]} i before=0 hasdo=0 why="" words
    while [ "$n" -gt 0 ] && [ -z "${lines[$((n-1))]//[[:space:]]/}" ]; do n=$((n-1)); done
    checked=$((checked+1))
    if [ "$n" -eq 0 ]; then bad "$fn" "the template prints nothing"; fn=""; return 0; fi
    if [ "$kind" = "plain" ]; then fn=""; return 0; fi

    case "${lines[0]}" in
        *.) : ;;
        *) bad "$fn" "line 1 must end with a period: ${lines[0]}" ;;
    esac

    for ((i = 0; i < n; i++)); do
        case "${lines[$i]}" in '  '*) break ;; esac
        before=$((before+1))
        case "${lines[$i]}" in
            'Do: '*)  hasdo=1 ;;
            'Why: '*) why="${lines[$i]#Why: }" ;;
        esac
    done
    [ "$before" -le 4 ] || bad "$fn" "$before lines before the paste block, four at most"
    [ "$hasdo" -eq 1 ] || bad "$fn" "no 'Do: ' line, and this message stops the reader"
    if [ "$kind" = "human" ] && [ -n "$why" ]; then
        words=$(printf '%s\n' "$why" | wc -w)
        [ "$words" -le 10 ] || bad "$fn" "the Why line runs $words words, ten at most"
    fi
    fn=""
}

registered=""
while IFS= read -r line; do
    case "$line" in
        '=== '*)
            check
            fn=${line#=== }
            kind=${fn##* }
            fn=${fn%% *}
            registered+=" $fn"
            lines=()
            ;;
        *) lines+=("$line") ;;
    esac
done < <(bash "$PLUGIN_ROOT/hooks/messages.sh" --raw)
check

if [ "$checked" -eq 0 ]; then
    echo "  FAIL the catalog is empty, so nothing was checked" >&2
    exit 1
fi

# Completeness: every msg_* template the file defines must appear in the
# catalog. An unregistered one is neither linted nor shape-checked, so its prose
# would ship unread, and nothing else would ever notice.
while IFS= read -r defined; do
    case " $registered " in
        *" $defined "*) : ;;
        *) bad "$defined" "defined in messages.sh but missing from the catalog" ;;
    esac
done < <(grep -oE '^msg_[A-Za-z0-9_]+\(\)' "$PLUGIN_ROOT/hooks/messages.sh" | sed 's/()$//' | sort -u)
printf '  %s %d templates checked, %d problem(s)\n' \
    "$([ "$fail" -eq 0 ] && echo ok  || echo FAIL)" "$checked" "$fail"
[ "$fail" -eq 0 ]
