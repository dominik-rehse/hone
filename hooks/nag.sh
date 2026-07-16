#!/bin/bash
# Stop-hook nag (Claude Code). The soft counterpart to the gate: cheap,
# deterministic hygiene checks that keep the durable layer from silently growing.
#
#   1. Leftover Plan   — a .plans/<change>.md whose change has LANDED: no
#      worktree, plus positive evidence the change concluded — the merge commit
#      land writes (its fixed -m format makes the grep exact) or a surviving
#      fully-merged hone/<change> branch. Consolidate should have deleted it.
#      "No worktree" alone is NOT evidence: that is the normal plan→run gap
#      (hone authors Plans first and runs them later, often from another
#      session), and flagging it nags every queued Plan into alarm fatigue.
#      Pending Plans get at most one aggregate advisory line. (A Plan whose
#      worktree still exists is active work — not flagged either way.)
#      <change> may be nested (auth/refresh-token): the plan skill derives
#      slugs mirroring src/, so the scan must recurse.
#   2. Oversized Note  — a docs/notes/<area>.md over the size cap (a Note is a
#      map + one invariant, not a spec: half a screen).
#   3. Orphan Note     — a docs/notes/<area>.md with no corresponding src/<area>/.
#      Notes are 1:1 with an existing area.
#   4. Change that cuts nothing — on a clean hone/<change> branch (committed,
#      about to land), the branch's whole diff against its merge base has zero
#      deletions. "Every cycle removes something" is the model's principle 4;
#      a purely additive change means consolidate pruned nothing. This check
#      stays advisory even under .hone-nag-enforce: a hard rule here would
#      incentivize token deletions, so the finding names the principle and
#      leaves the judgment to consolidate.
#   5. Landed branch left behind — in the PRIMARY tree, a hone/* branch fully
#      merged into HEAD with no worktree attached. Land removes the worktree;
#      the merged branch should go with it (git branch -d) or they accumulate
#      one per change, forever.
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
advisory=""
# Append one finding line with a real newline (the block emitter escapes it to a
# JSON \n; the advisory branch prints it as-is). add_advisory findings never
# block, even under .hone-nag-enforce (see check 4 in the header).
add_finding()  { findings+="- $1"$'\n'; }
add_advisory() { advisory+="- $1"$'\n'; }

# 1. Leftover Plan. Recurse: slugs are nested (.plans/<area>/<change>.md).
# Flag only on landed evidence (see the header); otherwise count as pending.
if [ -d ".plans" ]; then
    pending=0
    while IFS= read -r plan; do
        change=${plan#.plans/}
        change=${change%.md}
        [ -d ".worktrees/$change" ] && continue   # active work
        landed=""
        if git rev-parse --git-dir >/dev/null 2>&1; then
            if [ -n "$(git log --fixed-strings --grep="Merge branch 'hone/${change}'" -n 1 --format=%H 2>/dev/null)" ]; then
                landed="its landing merge commit is in history"
            elif git branch --merged HEAD --format='%(refname:short)' 2>/dev/null | grep -qxF "hone/$change"; then
                landed="branch hone/${change} is fully merged"
            fi
        fi
        if [ -n "$landed" ]; then
            add_finding "${plan} survived its landing (${landed}) — consolidate should have deleted the Plan; delete it (git keeps the history)."
        else
            pending=$((pending+1))
        fi
    done < <(find .plans -type f -name '*.md' 2>/dev/null)
    [ "$pending" -gt 0 ] && add_advisory "${pending} Plan(s) pending run in .plans/ — normal while queued; /hone:run picks them up."
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

# 4 + 5 need git.
if git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    GIT_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null)
    COMMON_DIR=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)

    # 4. Change that cuts nothing. Only on a clean hone/* branch (the pre-land
    # moment, same trigger as the gate's --all tier); mid-build churn is noise.
    # The merge target is whatever branch the PRIMARY tree has checked out.
    case "$BRANCH" in
        hone/*)
            if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
                primary_branch=$(git -C "$COMMON_DIR/.." rev-parse --abbrev-ref HEAD 2>/dev/null)
                base=$(git merge-base "$primary_branch" HEAD 2>/dev/null)
                if [ -n "$base" ]; then
                    stat=$(git diff --shortstat "$base" HEAD 2>/dev/null)
                    dels=$(printf '%s' "$stat" | grep -o '[0-9]* deletion' | grep -o '[0-9]*' || echo 0)
                    ins=$(printf '%s' "$stat" | grep -o '[0-9]* insertion' | grep -o '[0-9]*' || echo 0)
                    if [ "${ins:-0}" -gt 0 ] && [ "${dels:-0}" -eq 0 ]; then
                        add_advisory "this change deletes nothing (+${ins}/-0 vs ${primary_branch:-the merge base}) — every cycle removes something: a redundant test, dead code, a stale doc line. If consolidate truly found nothing to cut, say so in the landing commit body."
                    fi
                fi
            fi
            ;;
    esac

    # 5. Landed branch left behind. Primary tree only (in a linked worktree the
    # merged-into-HEAD question is about the wrong branch).
    if [ -n "$GIT_DIR" ] && [ "$GIT_DIR" = "$COMMON_DIR" ]; then
        attached=$(git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p')
        while IFS= read -r b; do
            [ -n "$b" ] || continue
            printf '%s\n' "$attached" | grep -qxF "$b" && continue   # a live worktree — active work
            add_finding "branch ${b} is fully merged and has no worktree — land should have deleted it (git branch -d ${b})."
        done < <(git branch --merged HEAD --format='%(refname:short)' 2>/dev/null | grep '^hone/')
    fi
fi

[ -z "$findings" ] && [ -z "$advisory" ] && exit 0

if [ -f ".hone-nag-enforce" ] && [ -n "$findings" ]; then
    # Advisory-only findings ride along in the block reason but never trigger it.
    hone_stop_block "hone nag found durable-layer hygiene issues — reconcile before finishing:"$'\n'"${findings}${advisory}"
    exit 0
fi

{
    printf 'hone nag (advisory — create .hone-nag-enforce to make these block):\n'
    printf '%s' "${findings}${advisory}"
} >&2
exit 0
