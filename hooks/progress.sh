#!/bin/bash
# Shows the run loop's progress lines to the person (PostToolUse and
# PostToolUseFailure on Bash, and Stop). The step subcommands of
# scripts/worktree.sh queue each line in <git-common-dir>/hone-progress/<session>
# (see progress_emit there). This hook takes its own session's queue and returns
# it as a systemMessage, which Claude Code shows in the terminal. A nonzero exit
# fires PostToolUseFailure, not PostToolUse, so a failed land shows too. Stop
# shows the line of a land that ran in the background.
#
# It only displays. It never blocks, and every failure ends in a silent exit 0.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

INPUT=$(cat)
SID=$(hone_extract_top_field "$INPUT" session_id)
case "$SID" in ""|*/*|.*) exit 0 ;; esac

DIR=$(hone_extract_top_field "$INPUT" cwd)
[ -d "$DIR" ] || DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
COMMON=$(cd "$DIR" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || exit 0
QUEUE="$COMMON/hone-progress/$SID"
[ -s "$QUEUE" ] || exit 0

# Take the queue in one rename, so a line worktree.sh appends meanwhile goes
# to a new queue, not into a file this hook is about to delete.
TAKEN="$QUEUE.$$"
mv -f "$QUEUE" "$TAKEN" 2>/dev/null || exit 0
LINES=$(cat "$TAKEN" 2>/dev/null)
rm -f "$TAKEN"
[ -n "$LINES" ] || exit 0
printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$LINES")"
exit 0
