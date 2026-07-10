#!/bin/bash
# Stop-hook nag (Claude Code). The soft counterpart to the gate: three cheap,
# deterministic hygiene checks that keep the durable layer from silently growing.
#
#   1. Leftover Plan   — a .plans/<change>.md with no matching .worktrees/<change>.
#      A Plan is deleted at consolidate; one left behind with no in-flight
#      worktree means the change landed (or was abandoned) without cleanup.
#      (A Plan whose worktree still exists is active work — not flagged.)
#      <change> may be nested (auth/refresh-token): the plan skill derives
#      slugs mirroring src/, so the scan must recurse.
#   2. Oversized Note  — a docs/notes/<area>.md over the size cap (a Note is a
#      map + one invariant, not a spec: half a screen).
#   3. Orphan Note     — a docs/notes/<area>.md with no corresponding src/<area>/.
#      Notes are 1:1 with an existing area.
#
# Default: ADVISORY — prints to stderr and exits 0 (never blocks). Create an
# empty .hone-nag-enforce to make the findings BLOCK the stop instead. Disabled
# entirely by .hone-off.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0

[ -f ".hone-off" ] && exit 0

# Note size cap: lines. "Half a screen" — a Note past this has drifted toward a
# spec and should be cut or split.
NOTE_MAX_LINES=40

findings=""
# Append one finding line with a real newline (the block emitter escapes it to a
# JSON \n; the advisory branch prints it as-is).
add_finding() { findings+="- $1"$'\n'; }

# 1. Leftover Plan. Recurse: slugs are nested (.plans/<area>/<change>.md).
if [ -d ".plans" ]; then
    while IFS= read -r plan; do
        change=${plan#.plans/}
        change=${change%.md}
        if [ ! -d ".worktrees/$change" ]; then
            add_finding "${plan} has no .worktrees/${change} — if the change landed, consolidate should have deleted the Plan; delete it (git keeps the history)."
        fi
    done < <(find .plans -type f -name '*.md' 2>/dev/null)
fi

# 2. Oversized Note.
if [ -d "docs/notes" ]; then
    for note in docs/notes/*.md; do
        [ -e "$note" ] || continue
        lines=$(wc -l < "$note" | tr -d '[:space:]')
        if [ "${lines:-0}" -gt "$NOTE_MAX_LINES" ]; then
            add_finding "${note} is ${lines} lines (cap ${NOTE_MAX_LINES}) — a Note is a map + one invariant, not a spec. Cut it, or push the detail into types/Decisions/tests."
        fi
    done
fi

# 3. Orphan Note. area = the note's basename; expect src/<area>/ to exist.
if [ -d "docs/notes" ]; then
    for note in docs/notes/*.md; do
        [ -e "$note" ] || continue
        area=$(basename "$note" .md)
        if [ ! -d "src/$area" ]; then
            add_finding "${note} has no src/${area}/ — a Note is 1:1 with an existing area (hone assumes a src/<area>/ layout). Rename it to its area, or delete it if the area is gone."
        fi
    done
fi

[ -z "$findings" ] && exit 0

if [ -f ".hone-nag-enforce" ]; then
    hone_stop_block "hone nag found durable-layer hygiene issues — reconcile before finishing:"$'\n'"${findings}"
    exit 0
fi

{
    printf 'hone nag (advisory — create .hone-nag-enforce to make these block):\n'
    printf '%s' "$findings"
} >&2
exit 0
