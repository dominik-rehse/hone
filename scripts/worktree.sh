#!/bin/bash
# hone worktree helper. The deterministic parts of the run loop's worktree
# handling, kept as a script so the parse is unit-testable; the run skill drives
# the actual `git worktree add` and the build/verify/consolidate steps around it.
#
#   worktree.sh add <change>
#       Create .worktrees/<change> on a new branch hone/<change> off HEAD, and
#       print its absolute path. Refuses if the worktree or branch already exists
#       (resume it, don't clobber). Exit: 0 created · 2 usage/not-a-repo/exists.
#
#   worktree.sh landable
#       Print "<worktree-path>\t<branch>" for every linked worktree on a branch
#       ahead of the current (primary) branch: the fan-in set for land. Excludes
#       the primary, detached-HEAD, and bare entries. Exit 0 if any, 1 if none,
#       2 if not a git repo.
#
#   worktree.sh remove <worktree-path>
#       Provenance-guarded cleanup. Removes the worktree ONLY if hone created it
#       (path under the main tree's .worktrees/); anything elsewhere is left for
#       its owner. Prunes stale registrations after; refuses to remove the tree
#       you are standing in. Then finishes the land's hygiene: deletes the
#       worktree's hone/* branch iff it is fully merged (`git branch -d`; an
#       unmerged branch is evidence and stays, with a note), and removes
#       now-empty parent dirs under .worktrees/ that a nested slug leaves
#       behind. Exit: 0 removed · 2 usage/not-a-repo/failed/self ·
#       3 left in place (not hone's to remove).
#
# Runs relative to the project root (git toplevel, else CLAUDE_PROJECT_DIR, else
# cwd, matching the hooks).

set -uo pipefail

cmd_add() {
    local change="${1:-}"
    [ -n "$change" ] || { echo "hone worktree: add needs a change name." >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "hone worktree: not a git repository." >&2; return 2; }

    # Anchor to the MAIN tree, not cwd: an orchestrator's shell cwd may sit inside
    # a sibling change's linked worktree, which would otherwise nest the new
    # worktree under it and branch off that sibling's unlanded HEAD. `git -C
    # "$main_root" … HEAD` resolves both the path and the base in the primary
    # checkout. Same provenance anchor cmd_remove uses.
    local main_root
    main_root=$(git -C "$(git rev-parse --git-common-dir 2>/dev/null)/.." rev-parse --show-toplevel 2>/dev/null)

    local path="$main_root/.worktrees/$change"
    local branch="hone/$change"
    [ -e "$path" ] && { echo "hone worktree: $path already exists — resume it or remove it first." >&2; return 2; }
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        echo "hone worktree: branch $branch already exists — resume that change or delete the branch first." >&2
        return 2
    fi

    mkdir -p "$main_root/.worktrees"
    git -C "$main_root" worktree add -q -b "$branch" "$path" HEAD || { echo "hone worktree: 'git worktree add' failed." >&2; return 2; }
    printf '%s\n' "$path"
}

# Parse `git worktree list --porcelain` (passed as $1), printing "<path>\t<branch>"
# for each worktree on a branch, excluding the primary at $2 and detached/bare
# entries. Pure text transform — no git, no cwd — so it is unit-testable.
parse_worktrees() {
    local porcelain="$1" primary="$2"
    printf '%s\n' "$porcelain" | awk -v primary="$primary" '
        function flush() {
            if (path != "" && path != primary && branch != "" && !det && !bare)
                printf "%s\t%s\n", path, branch
            path=""; branch=""; det=0; bare=0
        }
        /^worktree /  { flush(); path=substr($0, 10) }
        /^branch /    { branch=substr($0, 8); sub(/^refs\/heads\//, "", branch) }
        /^detached$/  { det=1 }
        /^bare$/      { bare=1 }
        END           { flush() }
    '
}

cmd_landable() {
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "hone worktree: not a git repository." >&2; return 2; }
    local primary target any=0 path branch ahead
    primary=$(git rev-parse --show-toplevel 2>/dev/null)
    target=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    while IFS=$'\t' read -r path branch; do
        [ -n "$branch" ] || continue
        ahead=$(git rev-list --count "$target..$branch" 2>/dev/null || echo 0)
        if [ "${ahead:-0}" -gt 0 ]; then printf '%s\t%s\n' "$path" "$branch"; any=1; fi
    done < <(parse_worktrees "$(git worktree list --porcelain 2>/dev/null)" "$primary")
    [ "$any" -eq 1 ] || { echo "hone worktree: no worktree is ahead of $target." >&2; return 1; }
}

cmd_remove() {
    local wt="${1:-}"
    [ -n "$wt" ] || { echo "hone worktree: remove needs a worktree path." >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "hone worktree: not a git repository." >&2; return 2; }

    # The MAIN tree's root — the common git dir's parent — so provenance is stable
    # even when this runs from inside a linked worktree.
    local main_root here
    main_root=$(git -C "$(git rev-parse --git-common-dir 2>/dev/null)/.." rev-parse --show-toplevel 2>/dev/null)
    here=$(git rev-parse --show-toplevel 2>/dev/null)

    case "$wt" in
        "$main_root"/.worktrees/*) : ;;
        *) echo "hone worktree: '$wt' is not under .worktrees/ — hone did not create it; leaving it for its owner." >&2; return 3 ;;
    esac
    [ "$here" = "$wt" ] && { echo "hone worktree: refusing to remove the worktree you are in ($wt); run land from the primary tree." >&2; return 2; }

    # Capture the branch this worktree has checked out BEFORE removing it.
    local branch
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)

    git worktree remove "$wt" || { echo "hone worktree: 'git worktree remove $wt' failed (uncommitted changes, or run from inside it?)." >&2; return 2; }
    git worktree prune

    # Land hygiene 1: a landed change's branch goes with its worktree. `-d`
    # (not -D) so an unmerged branch — abandoned or unlanded work — survives as
    # evidence rather than being destroyed.
    case "$branch" in
        hone/*)
            if ! git branch -d "$branch" >/dev/null 2>&1; then
                echo "hone worktree: kept branch $branch (not fully merged — evidence of unlanded work; delete with 'git branch -D $branch' only if abandoning it)." >&2
            fi
            ;;
    esac

    # Land hygiene 2: a nested slug (auth/refresh-token) leaves empty parent
    # dirs under .worktrees/ after removal; sweep them up to (not including)
    # .worktrees itself.
    local parent
    parent=$(dirname "$wt")
    while [ "$parent" != "$main_root/.worktrees" ] && [ "$parent" != "$main_root" ] && [ "$parent" != "/" ]; do
        rmdir "$parent" 2>/dev/null || break
        parent=$(dirname "$parent")
    done
}

main() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    [ -n "$root" ] || root="${CLAUDE_PROJECT_DIR:-$PWD}"
    cd "$root" || return 1
    local sub="${1:-}"; shift || true
    case "$sub" in
        add)      cmd_add "$@" ;;
        landable) cmd_landable "$@" ;;
        remove)   cmd_remove "$@" ;;
        *) echo "usage: worktree.sh {add <change>|landable|remove <worktree-path>}" >&2; return 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
