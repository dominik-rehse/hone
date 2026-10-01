#!/bin/bash
# Stop hook: a session that watches runs keeps a wait armed. The coordinator
# (skills/coordinate/SKILL.md) registers each session it starts with
# `scripts/coordinate.sh watch`. While one of those runs is still watched,
# this hook refuses to end the turn unless the session's `coordinate.sh wait`
# runs in the background. The wait wakes the session on the next land, stop,
# or question. Without it, a stop sat unseen until the person asked for
# status: 13 times in 7 sessions, up to 7 h 54 min
# (docs/spikes/2026-09-28-main-tracking-of-subs.md).
#
# On each Stop of a watching session it also starts the ticker again when the
# ticker died, so the notifications keep coming.
#
# Only a session that registered a watch is affected. Every other session
# (each run session included) finds no session file with its id, and the hook
# exits at once.
#
# The hook blocks at most twice in a row. The third Stop without a wait ends
# the turn and tells the person, so a session that cannot comply still gets
# its report out. The ticker notifies the person either way.
#
# It also pushes a turn end to the coordinator. In a session that a watch
# names by its herdr tab (HERDR_TAB_ID), each Stop appends one turn-ended
# event with the last line of the final message. The coordinator's wait wakes
# on it at once. Before, a stop that ended in text reached it only through the
# ticker's quiet event, 600 s later, and nothing followed a stopped event when
# the session finished its report. The event is skipped when the change landed
# or was planned since the watch began, when a stopped event came in the last
# 20 seconds, and when it repeats the session's last event word for word.
# This half never blocks and never prints.
#
# .hone-off disables it. Every failure ends in a silent exit 0.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/messages.sh"

COORD="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/scripts/coordinate.sh"
BLOCK_CAP=2

INPUT=$(cat 2>/dev/null)
SID=$(hone_extract_top_field "$INPUT" session_id)
case "$SID" in ""|*/*|.*) exit 0 ;; esac
DIR=$(hone_extract_top_field "$INPUT" cwd)
[ -d "$DIR" ] || DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$DIR" 2>/dev/null || exit 0
COMMON=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || exit 0
STATE="$COMMON/hone-coordinate"
[ -d "$STATE/sessions" ] || exit 0
[ -f "$COMMON/../.hone-off" ] && exit 0

# The last non-empty line of the session's final message: from the hook
# input, else from the transcript's last assistant text.
last_line() {
    local msg tp
    msg=$(hone_extract_top_field "$INPUT" last_assistant_message)
    tp=$(hone_extract_top_field "$INPUT" transcript_path)
    if [ -z "$msg" ] && [ -f "$tp" ] && command -v jq >/dev/null 2>&1; then
        msg=$(tail -n 400 "$tp" 2>/dev/null | jq -rs '[.[] | select(.type? == "assistant")
            | .message.content? | if type == "array" then .[] else empty end
            | select(.type? == "text") | .text] | last // empty' 2>/dev/null)
    fi
    printf '%s\n' "$msg" | sed 's/[[:space:]]*$//' | grep -v '^$' | tail -1 | sed -E 's/^[[:space:]]+//; s/^(.{160}).*/\1/'
}

# A session that a watch names by its tab: push its turn end.
if [ -n "${HERDR_TAB_ID:-}" ]; then
    for f in "$STATE"/sessions/*; do
        [ -f "$f" ] || continue
        grep -qxF "tab=$HERDR_TAB_ID" "$f" || continue
        change=$(sed -n 's/^change=//p' "$f" | head -1)
        since=$(sed -n 's/^registered=//p' "$f" | head -1)
        line=$(last_line)
        [ -n "$change" ] && [ -n "$line" ] || break
        awk -F'\t' -v c="$change" -v t="${since:-0}" -v now="$(date +%s)" -v d="$line" '
            $3 != c { next }
            ($4 == "landed" || $4 == "planned") && $2 >= t { skip = 1 }
            $4 == "stopped" && $2 >= now - 20 { skip = 1 }
            { k = $4; x = $5 }
            END { exit !(skip || (k == "turn-ended" && x == d)) }' "$STATE/events" 2>/dev/null && break
        hone_coord_event "$STATE" "$change" turn-ended "$line"
        break
    done
fi

mine=""
for f in "$STATE"/sessions/*; do
    [ -f "$f" ] || continue
    grep -qxF "owner=$SID" "$f" || continue
    change=$(sed -n 's/^change=//p' "$f")
    mine+="${change}  ($(basename "$f"))"$'\n'
done
[ -n "$mine" ] || exit 0

bash "$COORD" ensure >/dev/null 2>&1

COUNTER="$STATE/watch-block.$SID"
pid=$(cat "$STATE/wait.$SID.pid" 2>/dev/null)
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    rm -f "$COUNTER"
    exit 0
fi

n=$(( $(cat "$COUNTER" 2>/dev/null || echo 0) + 1 ))
if [ "$n" -gt "$BLOCK_CAP" ]; then
    rm -f "$COUNTER"
    printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$(msg_watch_let_go)")"
    exit 0
fi
printf '%s\n' "$n" > "$COUNTER"
hone_stop_block "$(msg_watch_no_wait "${mine%$'\n'}" "bash $COORD wait")"
exit 0
