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
#      session). Flagging it nags every queued Plan into alarm fatigue.
#      Pending Plans get at most one aggregate advisory line. (A Plan whose
#      worktree still exists is active work, and the nag does not flag it.)
#      <change> may be nested (auth/refresh-token): the plan skill derives
#      slugs mirroring src/, so the scan must recurse. The sibling-<dir>.md
#      signal below stays unambiguous because the plan skill refuses a slug
#      that collides with an existing Plan's directory (and vice versa).
#   2. Oversized Note: a docs/notes/<area>.md over the size cap (a Note is a
#      map + one invariant, not a spec: half a screen).
#   3. Orphan Note: a docs/notes/<area>.md with no corresponding src/<area>/.
#      Notes are 1:1 with an existing area.
#   8. Undated spike entry: anything directly under docs/spikes/ whose name
#      does not open with YYYY-MM-DD, of any type, file or directory. The date
#      is the whole signal that a spike is frozen history. So garden does not
#      touch it, and no reader mistakes it for a live document. Nothing else
#      about a spike is checkable: its size is whatever the investigation
#      needed, and its content is past tense by construction.
#   6. Broken Governs link: a Decision or Note declaring `Governs: <path>` whose
#      path no longer exists. The optional `Governs:` line pins durable prose
#      to the code it explains. When the code moves or a change deletes it, the
#      dangling reference is mechanical proof the doc drifted. The check reads
#      only path-shaped tokens (containing "/"), so it is exact. Symbol-level
#      drift stays the consolidate-critic's judgment call. This is the
#      mechanical half of catching the one staleness the model warns can pass
#      silently (unverified prose): a hook, not a once-run critic.
#   9. Broken relative link: a markdown link in a Decision or Note whose
#      target does not resolve from the doc's directory. Same reasoning as
#      the Governs check: the target exists or it does not, so the check is
#      exact. URLs and #anchors are not files, and the check skips them.
#      Backticked prose paths stay unchecked: prose legitimately names
#      example paths, and a stateless nag cannot be told a finding is
#      intentional.
#   4. Change that cuts nothing: on a clean hone/<change> branch (committed,
#      about to land), the branch's whole diff against its merge base has zero
#      deletions. "Every cycle removes something" is the model's principle 4.
#      A purely additive change means consolidate pruned nothing. A hard rule
#      here would incentivize token deletions, so the finding names the
#      principle and leaves the judgment to consolidate.
#   5. Landed branch left behind: in the PRIMARY tree, a hone/* branch fully
#      merged into HEAD with no worktree attached. Land removes the worktree.
#      The merged branch should go with it (git branch -d), or they accumulate
#      one per change, forever.
#   7. Durable truth stranded in harness memory: a `type: project` memory file
#      under the harness's per-project memory directory. That directory is the
#      agent harness's own store, outside the repo: per-user, uncommitted,
#      unreviewed, and invisible to garden. So a decision or constraint left
#      there governs nothing. Types `user`/`feedback`/`reference` are the
#      human's own, and the nag does not check them. The file belongs to the
#      human, so hone names it and never touches it.
#
# The nag is ADVISORY: it reports its findings and exits 0, never blocking the
# stop (the gate is the blocking hook). Findings go out as a {"systemMessage":
# ...} on stdout, the one non-blocking channel a Stop hook has that the harness
# actually shows. Stderr on exit 0 reaches neither the model nor the user.
# .hone-off disables the nag entirely.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/messages.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0

[ -f ".hone-off" ] && exit 0

# Note size cap: lines. "Half a screen". A Note past this has drifted toward a
# spec and needs a cut or a split.
NOTE_MAX_LINES=40

findings=""
# One finding is a three-line template (what happened, Do, Why). Render it as a
# list item: a dash on the first line, the rest indented under it.
add_finding() {
    findings+=$(printf '%s\n' "$1" | sed '1s/^/- /; 2,$s/^/  /')$'\n'
}

# 1. Leftover Plan. Recurse: slugs are nested (.plans/<area>/<change>.md).
# Flag only on landed evidence (see the header). Otherwise count as pending.
if [ -d ".plans" ]; then
    pending=0
    while IFS= read -r plan; do
        # A markdown file inside .plans/<slug>/ is one of the Plan's REFERENCES,
        # not a Plan. The plan skill puts them in a directory named for the Plan
        # beside it, so the signal is a sibling <dir>.md. Without this, the nag
        # would count a reference as a pending Plan that never runs.
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
            add_finding "$(msg_nag_plan_survived "$plan" "$landed")"
        else
            pending=$((pending+1))
        fi
    done < <(find .plans -type f -name '*.md' 2>/dev/null)
    [ "$pending" -gt 0 ] && add_finding "$(msg_nag_plans_pending "$pending")"
fi

# 2. Oversized Note.
if [ -d "docs/notes" ]; then
    for note in docs/notes/*.md; do
        [ -e "$note" ] || continue
        lines=$(wc -l < "$note" | tr -d '[:space:]')
        if [ "${lines:-0}" -gt "$NOTE_MAX_LINES" ]; then
            add_finding "$(msg_nag_note_oversized "$note" "$lines" "$NOTE_MAX_LINES")"
        fi
    done
fi

# 3. Orphan Note. area = the note's basename. Expect src/<area>/ to exist.
if [ -d "docs/notes" ]; then
    for note in docs/notes/*.md; do
        [ -e "$note" ] || continue
        area=$(basename "$note" .md)
        if [ ! -d "src/$area" ]; then
            add_finding "$(msg_nag_note_orphan "$note" "$area")"
        fi
    done
fi

# 8. Undated spike entry. Everything one spike leaves behind lives under
# docs/spikes/ and shares a dated stem, whatever its type. That covers the
# note, the probe that produced it, a mockup, a captured payload. The date at
# the front is what says "frozen history" to a reader and to garden. So check
# every entry at the top level, not only the markdown. A spike with several
# files uses a dated DIRECTORY, which this checks the same way, and never looks
# inside. What a probe names its own files is the probe's business.
if [ -d "docs/spikes" ]; then
    for spike in docs/spikes/*; do
        [ -e "$spike" ] || continue
        case "$(basename "$spike")" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) ;;
            *) add_finding "$(msg_nag_spike_undated "$spike")" ;;
        esac
    done
fi

# 6. Broken Governs link. A Decision or Note may declare a `Governs:` line
# naming the src/ paths it explains. A dangling path proves the prose drifted
# from the code. Path-shaped tokens only (exact existence check). The parse
# strips backticks and trailing commas and periods, so
# `Governs: `src/auth/token.ts`, ...` parses.
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
                */*) [ -e "$tok" ] || add_finding "$(msg_nag_governs_broken "$doc" "$tok")" ;;
            esac
        done
    done < <(find docs/decisions docs/notes -type f -name '*.md' 2>/dev/null)
fi

# 9. Broken relative link. A markdown link target in a Decision or Note either
# resolves from the doc's directory or it does not, so the check needs no
# judgment. URLs and #anchors are not files. A title after the target
# (`](x.md "Title")`) and a #fragment are stripped before the check.
if [ -d "docs/decisions" ] || [ -d "docs/notes" ]; then
    while IFS= read -r doc; do
        [ -e "$doc" ] || continue
        while IFS= read -r target; do
            case "$target" in
                ''|*://*|mailto:*|'#'*|/*) continue ;;
            esac
            target=${target%%#*}      # drop a fragment
            target=${target%% *}      # drop a link title
            [ -n "$target" ] || continue
            [ -e "$(dirname "$doc")/$target" ] || add_finding "$(msg_nag_link_broken "$doc" "$target")"
        done < <(grep -oE '\]\([^)]+\)' "$doc" 2>/dev/null | sed 's/^](//; s/)$//')
    done < <(find docs/decisions docs/notes -type f -name '*.md' 2>/dev/null)
fi

# 7. Durable truth stranded in harness memory. The harness keys its per-project
# memory directory by the project's absolute path with "/" replaced by "-". That
# key is an undocumented harness detail, so this check FAILS OPEN: an absent or
# renamed directory simply yields nothing, never a false finding. The check
# tries both the symlink-resolved and the as-given project path, since the
# harness may have keyed on either.
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
            add_finding "$(msg_nag_memory_project "$(basename "$mem")" "${mem_dir/#$HOME/\~}")"
        done < <(grep -rlE '^[[:space:]]*type:[[:space:]]*project[[:space:]]*$' "$mem_dir" --include='*.md' 2>/dev/null)
    done
fi

# 4 + 5 need git.
if git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    GIT_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null)
    COMMON_DIR=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)

    # 4. Change that cuts nothing. Only on a clean hone/* branch (the pre-land
    # moment, same trigger as the gate's --all tier). Mid-build churn is noise.
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
                        add_finding "$(msg_nag_no_deletions "$ins" "${primary_branch:-the merge base}")"
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
            add_finding "$(msg_nag_merged_branch "$b")"
        done < <(git branch --merged HEAD --format='%(refname:short)' 2>/dev/null | grep '^hone/')
    fi
fi

[ -z "$findings" ] && exit 0

printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$(msg_nag_header)
${findings%$'\n'}")"
exit 0
