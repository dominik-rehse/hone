#!/bin/bash
# hone worktree helper. The deterministic parts of the run loop's worktree
# handling, kept as a script so the parse is unit-testable; the run skill drives
# the actual `git worktree add` and the build/verify/consolidate steps around it.
#
#   worktree.sh add <change>
#       Create .worktrees/<change> on a new branch hone/<change> off HEAD, and
#       print its absolute path. The worktree+branch ARE the change's claim:
#       creation is atomic (git makes the branch ref), so of two runs racing on
#       one change exactly one wins. Refuses if the worktree or branch already
#       exists — another run owns it, or it is leftover evidence to resume by
#       hand. Exit: 0 created · 4 already claimed · 2 usage/not-a-repo/failed.
#
#   worktree.sh land <change>
#       Land hone/<change> into the primary tree, serialized against every other
#       session that shares it. Takes an flock on <git-common-dir>/hone-land.lock
#       (waits up to HONE_LAND_LOCK_TIMEOUT s, default 600) and, while held,
#       merges --no-ff, re-runs scripts/run-tests.sh --all in the primary tree,
#       and on green removes the worktree + deletes the branch. Any failure
#       leaves the primary tree clean and green (a conflict is aborted, a
#       post-merge regression is rolled back) with the worktree/branch kept as
#       evidence. Run from the primary tree, after committing in the worktree.
#       Authority gate (opt-in via .hone-require-grant): a CONSEQUENTIAL change
#       (destructive SQL, a db/ deletion, or a .hone-consequential-paths match)
#       may not merge without a scoped grant at .hone-grant/<change>; without it
#       land refuses BEFORE the merge and keeps the worktree as evidence. The
#       grant's text rides into the merge commit body, so the authorization
#       lives in durable history rather than a chat.
#       Proof gate (opt-in via .hone-proof-enforce): a change whose Plan declared
#       real-environment proof (a `Proof: real-environment` trailer on a branch
#       commit) may not land on the gate's assertion-level suite alone; it must be
#       discharged by scripts/proof.sh (green) or an attestation at
#       .hone-proof/<change>, else land refuses BEFORE the merge.
#       Exit: 0 landed · 2 usage/not-a-repo/detached/conflict · 5 lock timeout ·
#       6 post-merge regression (rolled back) · 7 real-environment proof not
#       discharged · 8 ungranted consequential change.
#
#   worktree.sh verify
#       Run the full suite (scripts/run-tests.sh --all) in the current tree,
#       serialized under the SAME lock as land. e2e tiers are load-sensitive:
#       two concurrent full suites poison each other's signal (phantom flakes),
#       and a suite racing a land's re-verify produces spurious rollbacks — so
#       every full-suite run shares the one lock. This is the sanctioned way to
#       run --all by hand; never invoke the adapter bare for a full run. The
#       fast unit tier needs no lock and no wrapper. Exit: the adapter's exit ·
#       2 usage/not-a-repo/no-adapter · 5 lock timeout.
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
    # The worktree/branch is the change's claim. "Already exists" is exit 4
    # (claimed), distinct from a real failure (2), so a `run` can tell "another
    # run owns this — skip it" from "something broke".
    [ -e "$path" ] && { echo "hone worktree: $path already exists — another run owns this change, or it is leftover evidence to resume by hand." >&2; return 4; }
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        echo "hone worktree: branch $branch already exists — another run owns this change, or it is leftover evidence to resume by hand." >&2
        return 4
    fi

    mkdir -p "$main_root/.worktrees"
    if ! git -C "$main_root" worktree add -q -b "$branch" "$path" HEAD; then
        # The pre-checks passed but the add still failed: either a concurrent run
        # just claimed this change (the atomic branch-ref creation lost the race)
        # or a genuine error. If the claim now exists, report it as claimed (4).
        if git show-ref --verify --quiet "refs/heads/$branch" || [ -e "$path" ]; then
            echo "hone worktree: $branch was just claimed by a concurrent run." >&2
            return 4
        fi
        echo "hone worktree: 'git worktree add' failed." >&2
        return 2
    fi
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

cmd_verify() {
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "hone worktree: not a git repository." >&2; return 2; }
    [ -f "scripts/run-tests.sh" ] || { echo "hone worktree: no scripts/run-tests.sh adapter here — run setup.sh first." >&2; return 2; }
    command -v flock >/dev/null 2>&1 || { echo "hone worktree: 'flock' not found — cannot serialize the full suite across sessions; install util-linux." >&2; return 2; }

    local lock timeout
    lock="$(git rev-parse --git-common-dir 2>/dev/null)/hone-land.lock"
    timeout="${HONE_LAND_LOCK_TIMEOUT:-600}"
    # Land's lock, on purpose: a full suite must never overlap another full
    # suite OR a land's merge/re-verify. One lock makes both exclusions hold.
    exec 9>"$lock" || { echo "hone worktree: cannot open the suite lock at $lock." >&2; return 2; }
    flock -w "$timeout" 9 || { echo "hone worktree: another session held the suite lock for >${timeout}s (a land or full-suite run); retry." >&2; return 5; }
    bash scripts/run-tests.sh --all
}

# Classify a branch about to land as CONSEQUENTIAL — an effectively irreversible
# or high-blast-radius change — printing one reason line per signal (empty output
# = reversible). Reversibility is the axis: a bad reversible merge is undone with
# `git revert`; a dropped column is not. Only consulted when .hone-require-grant
# is present (see cmd_land), so a project whose changes are all reversible
# (undeployed software, disposable dev data) is never gated. Signals: destructive
# SQL in a migration or db/ file, a deletion under db/, and any path glob the
# project lists in .hone-consequential-paths. Git pathspecs do the matching.
land_consequential() {
    local root="$1" branch="$2" base reasons=""
    base=$(git -C "$root" merge-base HEAD "$branch" 2>/dev/null)
    [ -n "$base" ] || return 0
    if git -C "$root" diff "$base" "$branch" -- db ':(glob)**/migrations/**' 2>/dev/null \
        | grep -E '^\+' | grep -qiE 'DROP[[:space:]]+(TABLE|COLUMN)|TRUNCATE|DELETE[[:space:]]+FROM|ALTER[[:space:]].+DROP'; then
        reasons+="  - destructive SQL (DROP/TRUNCATE/DELETE/ALTER…DROP) in a migration or db/ file"$'\n'
    fi
    if git -C "$root" diff --diff-filter=D --name-only "$base" "$branch" -- db 2>/dev/null | grep -q .; then
        reasons+="  - a file under db/ is deleted"$'\n'
    fi
    if [ -f "$root/.hone-consequential-paths" ]; then
        local pat
        while IFS= read -r pat; do
            [ -n "$pat" ] || continue
            case "$pat" in \#*) continue ;; esac
            if git -C "$root" diff --name-only "$base" "$branch" -- ":(glob)$pat" 2>/dev/null | grep -q .; then
                reasons+="  - touches a consequential path: $pat"$'\n'
            fi
        done < "$root/.hone-consequential-paths"
    fi
    printf '%s' "$reasons"
}

# Print non-empty if the branch declares real-environment proof — a `Proof:
# real-environment` trailer in any of its commit messages (the run skill copies
# the Plan's proof class there). Only consulted when .hone-proof-enforce is
# present. A change with no such trailer is assertion-class: the gate's suite
# already proves it, and it is never gated here — so a project that never declares
# real-environment proof is unaffected even with the marker on.
land_proof_required() {
    local root="$1" branch="$2" base
    base=$(git -C "$root" merge-base HEAD "$branch" 2>/dev/null)
    [ -n "$base" ] || return 0
    git -C "$root" log --format=%B "$base..$branch" 2>/dev/null \
        | grep -qiE '^[[:space:]]*Proof:[[:space:]]*real-environment' && echo yes
}

cmd_land() {
    local change="${1:-}"
    [ -n "$change" ] || { echo "hone worktree: land needs a change name." >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "hone worktree: not a git repository." >&2; return 2; }
    command -v flock >/dev/null 2>&1 || { echo "hone worktree: 'flock' not found — cannot serialize the land across sessions; install util-linux." >&2; return 2; }

    local common_dir main_root branch wt lock timeout
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    main_root=$(git -C "$common_dir/.." rev-parse --show-toplevel 2>/dev/null)
    branch="hone/$change"
    wt="$main_root/.worktrees/$change"
    lock="$common_dir/hone-land.lock"
    timeout="${HONE_LAND_LOCK_TIMEOUT:-600}"

    # Serialize the WHOLE land (merge → re-verify → cleanup) against every session
    # sharing this primary tree. One flock, held for the critical section by this
    # process and auto-released if it dies (so a killed land leaves no stale
    # lock). A concurrent land waits up to $timeout rather than interleaving on
    # the shared HEAD/index/worktree. Everything that reads or moves the primary
    # tree lives inside the lock — checking outside it would be a TOCTOU race.
    exec 9>"$lock" || { echo "hone worktree: cannot open the land lock at $lock." >&2; return 2; }
    flock -w "$timeout" 9 || { echo "hone worktree: another land held the lock for >${timeout}s; retry." >&2; return 5; }

    git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch" || {
        echo "hone worktree: branch $branch does not exist — nothing to land." >&2; return 2; }
    git -C "$main_root" symbolic-ref -q HEAD >/dev/null || {
        echo "hone worktree: the primary tree is in detached HEAD — restore it to the trunk before landing." >&2; return 2; }

    # Authority gate (opt-in via .hone-require-grant): a CONSEQUENTIAL change needs
    # a scoped human grant before it may merge. Capability (guard/bash-guard) is
    # "can the agent act"; this is the separate contract — "may it, for this
    # irreversible act". Checked BEFORE the merge so an ungranted consequential
    # change never touches the trunk. The grant is scoped (one change), revocable
    # (delete the file), auditable (its text lands in the merge body below), and
    # recoverable (the worktree stays until it is granted).
    local grant_note=""
    if [ -f "$main_root/.hone-require-grant" ]; then
        local reasons grant
        reasons=$(land_consequential "$main_root" "$branch")
        if [ -n "$reasons" ]; then
            grant="$main_root/.hone-grant/$change"
            if [ ! -f "$grant" ]; then
                {
                    echo "hone worktree: $branch is a CONSEQUENTIAL change and has no authority grant:"
                    printf '%s' "$reasons"
                    echo "Review the diff. If you authorize it, record who/when/why in a file at"
                    echo "  .hone-grant/$change  (gitignored, per-developer)"
                    echo "then re-run land. The worktree is kept as evidence until then."
                } >&2
                return 8
            fi
            grant_note=$(cat "$grant" 2>/dev/null)
        fi
    fi

    # Proof gate (opt-in via .hone-proof-enforce): a change whose Plan declared
    # real-environment proof cannot land on the gate's assertion-level suite alone
    # — a green check proves only its assertion, not a browser journey or deployed
    # health. Discharge it with a real-environment adapter (scripts/proof.sh, which
    # checks the real environment, not the working tree) or a human attestation
    # (.hone-proof/<change>); otherwise land refuses before the merge and escalates.
    if [ -f "$main_root/.hone-proof-enforce" ] && [ -n "$(land_proof_required "$main_root" "$branch")" ]; then
        if [ -f "$main_root/.hone-proof/$change" ]; then
            : # human attested the real-environment check ran
        elif [ -f "$main_root/scripts/proof.sh" ]; then
            if ! ( cd "$main_root" && bash scripts/proof.sh ); then
                echo "hone worktree: $branch declares real-environment proof and scripts/proof.sh failed — the change is not proven in the real environment. Worktree kept as evidence." >&2
                return 7
            fi
        else
            {
                echo "hone worktree: $branch declares real-environment proof, which the gate's suite cannot give (a green check proves only its assertion)."
                echo "Discharge it one of two ways, then re-run land:"
                echo "  - add scripts/proof.sh (a real-environment check: a journey, a canary, deployed health), or"
                echo "  - run the check yourself and attest it in a file at .hone-proof/$change (gitignored)."
                echo "The worktree is kept as evidence until then."
            } >&2
            return 7
        fi
    fi

    local pre; pre=$(git -C "$main_root" rev-parse HEAD)
    local -a merge_args=(merge --no-ff "$branch" -m "Merge branch '$branch'")
    # The grant's text becomes a second commit paragraph — the authorization is
    # then in git history. The first line stays "Merge branch 'hone/<change>'" so
    # the nag's landed-Plan grep still matches.
    [ -n "$grant_note" ] && merge_args+=(-m "Authorized (consequential change):"$'\n'"$grant_note")
    if ! git -C "$main_root" "${merge_args[@]}" >/dev/null 2>&1; then
        # A conflict means the independence check missed a seam. Restore the
        # shared tree so the next lander starts clean; the branch stays as
        # evidence to fold in serially.
        git -C "$main_root" merge --abort 2>/dev/null
        echo "hone worktree: merging $branch conflicted — the independence check missed a seam. Primary tree restored; branch kept. Fold this change in serially." >&2
        return 2
    fi
    if ! ( cd "$main_root" && bash scripts/run-tests.sh --all >/dev/null 2>&1 ); then
        # Green would confirm the merge; red means it regressed the trunk. Roll
        # the merge back so the shared tree is left green for the next lander;
        # the worktree/branch survive for investigation.
        git -C "$main_root" reset --hard "$pre" >/dev/null 2>&1
        echo "hone worktree: suite RED in the primary tree after merging $branch — the merge regresses the trunk. Rolled back; worktree kept as evidence. Investigate before retrying." >&2
        return 6
    fi
    # Green: the merge is confirmed. Retire the worktree and its branch (cmd_remove
    # runs from the primary tree, so it never refuses "the tree you are in").
    cmd_remove "$wt"
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
        verify)   cmd_verify "$@" ;;
        land)     cmd_land "$@" ;;
        remove)   cmd_remove "$@" ;;
        *) echo "usage: worktree.sh {add <change>|landable|verify|land <change>|remove <worktree-path>}" >&2; return 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
