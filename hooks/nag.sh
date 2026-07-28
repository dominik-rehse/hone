#!/bin/bash
# Stop-hook nag (Claude Code). The soft counterpart to the gate: cheap,
# deterministic hygiene checks that keep the durable layer from silently growing.
#
#   1. Leftover Plan: a .plans/<change>.md whose change has LANDED: no
#      worktree, plus positive evidence the change concluded. The merge commit
#      land writes (its fixed -m format makes the grep exact) or a surviving
#      fully-merged hone/<change> branch. Consolidate should have deleted it.
#      "No worktree" alone is NOT evidence: that is the normal plan→run gap
#      (hone authors Plans first and runs them later, often from another
#      session), and flagging it nags every queued Plan into alarm fatigue.
#      Pending Plans get at most one aggregate advisory line. (A Plan whose
#      worktree still exists is active work, not flagged either way.)
#      <change> may be nested (auth/refresh-token): the plan skill derives
#      slugs mirroring src/, so the scan must recurse. The sibling-<dir>.md
#      giveaway below stays unambiguous because the plan skill refuses a slug
#      that collides with an existing Plan's directory (and vice versa).
#   2. Oversized Note: a docs/notes/<area>.md over the size cap (a Note is a
#      map + one invariant, not a spec: half a screen).
#   3. Orphan Note: a docs/notes/<area>.md with no corresponding src/<area>/.
#      Notes are 1:1 with an existing area.
#   6. Broken Governs link: a Decision or Note declaring `Governs: <path>` whose
#      path no longer exists. The optional `Governs:` line pins durable prose to
#      the code it explains: when the code moves or is deleted, the dangling
#      reference is mechanical proof the doc drifted. Only path-shaped tokens
#      (containing "/") are checked (exact and unfoolable); symbol-level drift
#      stays the consolidate-critic's judgment call. This is the mechanical half
#      of catching the one staleness the model warns can pass silently (unverified
#      prose): a hook, not a once-run critic.
#   4. Change that cuts nothing: on a clean hone/<change> branch (committed,
#      about to land), the branch's whole diff against its merge base has zero
#      deletions. "Every cycle removes something" is the model's principle 4;
#      a purely additive change means consolidate pruned nothing. A hard rule
#      here would incentivize token deletions, so the finding names the
#      principle and leaves the judgment to consolidate.
#   5. Landed branch left behind: in the PRIMARY tree, a hone/* branch fully
#      merged into HEAD with no worktree attached. Land removes the worktree;
#      the merged branch should go with it (git branch -d) or they accumulate
#      one per change, forever.
#   7. Durable truth stranded in harness memory: a `type: project` memory file
#      under the harness's per-project memory directory. That directory is the
#      agent harness's own store, outside the repo: per-user, uncommitted,
#      unreviewed, and invisible to garden, so a decision or constraint left
#      there governs nothing. Types `user`/`feedback`/`reference` are the
#      human's own and are not checked. The file belongs to the human, so hone
#      names it and never touches it.
#
# The nag is ADVISORY: it reports its findings and exits 0, never blocking the
# stop (the gate is the blocking hook). Findings ride a {"systemMessage": ...}
# on stdout — the one non-blocking channel a Stop hook has that is actually
# shown (stderr on exit 0 reaches neither the model nor the user). Disabled
# entirely by .hone-off.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0

[ -f ".hone-off" ] && exit 0

# Note size cap: lines. "Half a screen". A Note past this has drifted toward a
# spec and should be cut or split.
NOTE_MAX_LINES=40

findings=""
add_finding() { findings+="- $1"$'\n'; }

# 1. Leftover Plan. Recurse: slugs are nested (.plans/<area>/<change>.md).
# Flag only on landed evidence (see the header); otherwise count as pending.
if [ -d ".plans" ]; then
    pending=0
    while IFS= read -r plan; do
        # A markdown file inside .plans/<slug>/ is one of the Plan's REFERENCES,
        # not a Plan: the plan skill puts them in a directory named for the Plan
        # beside it, so the giveaway is a sibling <dir>.md. Without this, a
        # reference would be counted as a pending Plan that never runs.
        [ -f "$(dirname "$plan").md" ] && continue
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
    [ "$pending" -gt 0 ] && add_finding "${pending} Plan(s) pending run in .plans/ — normal while queued; /hone:run picks them up."
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

# 6. Broken Governs link. A Decision or Note may declare a `Governs:` line naming
# the src/ paths it explains; a dangling path proves the prose drifted from the
# code. Path-shaped tokens only (exact existence check); backticks and trailing
# commas/periods are stripped so `Governs: `src/auth/token.ts`, ...` parses.
if [ -d "docs/decisions" ] || [ -d "docs/notes" ]; then
    while IFS= read -r doc; do
        [ -e "$doc" ] || continue
        gov=$(grep -im1 '^[[:space:]]*[Gg]overns:' "$doc" 2>/dev/null | sed 's/.*[Gg]overns:[[:space:]]*//')
        [ -n "$gov" ] || continue
        gov=${gov//\`/}          # drop backticks
        gov=${gov//,/ }          # commas → separators
        for tok in $gov; do
            tok=${tok%.}         # strip a trailing period
            case "$tok" in
                */*) [ -e "$tok" ] || add_finding "${doc} declares Governs: ${tok}, which no longer exists — this durable doc has drifted from the code it governs. Update the reference, or cut the doc if the code is gone." ;;
            esac
        done
    done < <(find docs/decisions docs/notes -type f -name '*.md' 2>/dev/null)
fi

# 7. Durable truth stranded in harness memory. The harness keys its per-project
# memory directory by the project's absolute path with "/" replaced by "-". That
# key is an undocumented harness detail, so this check FAILS OPEN: an absent or
# renamed directory simply yields nothing, never a false finding. Both the
# symlink-resolved and the as-given project path are tried, since the harness may
# have keyed on either.
MEM_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
if [ -d "$MEM_ROOT" ]; then
    seen_mem=""
    for candidate in "$(pwd -P)" "$PROJECT_ROOT"; do
        mem_dir="$MEM_ROOT/$(printf '%s' "$candidate" | tr '/' '-')/memory"
        [ -d "$mem_dir" ] || continue
        case "$seen_mem" in *"|$mem_dir|"*) continue ;; esac
        seen_mem="$seen_mem|$mem_dir|"
        while IFS= read -r mem; do
            [ -n "$mem" ] || continue
            add_finding "$(basename "$mem") is a 'type: project' harness memory in ${mem_dir/#$HOME/\~} — that store is per-user, uncommitted, and invisible to the critics and garden, so a decision or constraint there governs nothing. If it belongs to the codebase, land it as a Decision or Note through consolidate."
        done < <(grep -rlE '^[[:space:]]*type:[[:space:]]*project[[:space:]]*$' "$mem_dir" --include='*.md' 2>/dev/null)
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
                        add_finding "this change deletes nothing (+${ins}/-0 vs ${primary_branch:-the merge base}) — every cycle removes something: a redundant test, dead code, a stale doc line. If consolidate truly found nothing to cut, say so in the landing commit body."
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
            printf '%s\n' "$attached" | grep -qxF "$b" && continue   # a live worktree, active work
            add_finding "branch ${b} is fully merged and has no worktree — land should have deleted it (git branch -d ${b})."
        done < <(git branch --merged HEAD --format='%(refname:short)' 2>/dev/null | grep '^hone/')
    fi
fi

[ -z "$findings" ] && exit 0

printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "hone nag (advisory):
${findings%$'\n'}")"
exit 0
