#!/bin/bash
# Stop hook: a session that watches runs keeps a wait armed. A session under
# herdr (MAIN of `--all`) registers each run it starts with
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
