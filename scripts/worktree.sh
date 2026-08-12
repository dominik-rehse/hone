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
#       exists: another run owns it, or it is leftover evidence to resume by
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
#       Authority gate: an IRREVERSIBLE change (destructive SQL, a db/ deletion,
#       or a .hone-irreversible-paths match) may not merge without a scoped
#       grant at .hone-grant/<change>; without it land refuses BEFORE the merge
#       and keeps the worktree as evidence. The grant's text rides into the
#       merge commit body, so the authorization lives in durable history rather
#       than a chat.
#       Proof gate: a change whose Plan declared real-environment proof (a
#       `Proof: real-environment` trailer on a branch commit) may not land on
#       the test suite alone. Satisfy it either with a green scripts/proof.sh
#       (the PRIMARY tree's reviewed copy, executed from the change's WORKTREE,
#       since that tree holds the code under test; running the change's own copy
#       would let it ship a green stub, with HONE_CHANGE/HONE_BRANCH/
#       HONE_WORKTREE/HONE_MAIN_ROOT in its environment) or with a human
#       sign-off at .hone-proof/<change> that names the commit it proved, so a
#       sign-off cannot outlive the code it attested. Else land refuses BEFORE
#       the merge.
#       Exit: 0 landed · 2 usage/not-a-repo/detached · 5 lock timeout ·
#       6 post-merge regression (rolled back) · 7 real-environment proof
#       missing · 8 ungranted irreversible change · 9 merge conflict
#       (aborted, tree restored).
#
#   worktree.sh verify
#       Run the full suite (scripts/run-tests.sh --all) in the current tree,
#       serialized under the SAME lock as land. e2e tiers are load-sensitive:
#       two concurrent full suites poison each other's signal (phantom flakes),
#       and a suite racing a land's re-verify produces spurious rollbacks, so
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
#   worktree.sh status
#       One-screen state of the control surface: hooks on/off, adapters
#       present, policy files (and whether they are committed), pending Plans,
#       worktrees in flight, grants and proof sign-offs, and whether the
#       settings.json deny rules are installed. Read-only; always exit 0 in a
#       git repo.
#
#   worktree.sh grant <change> "who/why"
#       Record the human's authority grant for one irreversible change at
#       .hone-grant/<change>, stamped with the git user and the current time.
#       FOR THE HUMAN's own terminal: the bash-guard denies an agent running
#       it, because exits 7/8 are reserved to the human by design.
#
#   worktree.sh attest <change> "what you ran"
#       Record the human's real-environment sign-off at .hone-proof/<change>,
#       stamped with the branch tip it proves (so it stops counting after new
#       commits), the git user, and the time. FOR THE HUMAN, like grant.
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

# This script's own absolute path, for remedy messages: the human runs the
# grant/attest helpers in their own terminal, where ${CLAUDE_PLUGIN_ROOT} is
# not set, so a bare "worktree.sh ..." would be a dead end.
HONE_WSH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/worktree.sh"
HONE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The plugin layout is fixed: scripts/ and hooks/ are siblings.
# shellcheck source=hooks/common.sh
. "$HONE_PLUGIN_ROOT/hooks/common.sh"
# shellcheck source=hooks/messages.sh
. "$HONE_PLUGIN_ROOT/hooks/messages.sh"

cmd_add() {
    local change="${1:-}"
    [ -n "$change" ] || { msg_wt_needs_change add >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }

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
    # run owns this, skip it" from "something broke".
    [ -e "$path" ] && { msg_wt_add_path_claimed "$path" >&2; return 4; }
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        msg_wt_add_branch_claimed "$branch" >&2
        return 4
    fi

    mkdir -p "$main_root/.worktrees"
    if ! git -C "$main_root" worktree add -q -b "$branch" "$path" HEAD; then
        # The pre-checks passed but the add still failed: either a concurrent run
        # just claimed this change (the atomic branch-ref creation lost the race)
        # or a genuine error. If the claim now exists, report it as claimed (4).
        if git show-ref --verify --quiet "refs/heads/$branch" || [ -e "$path" ]; then
            msg_wt_add_race "$branch" >&2
            return 4
        fi
        msg_wt_add_failed >&2
        return 2
    fi
    printf '%s\n' "$path"
}

# Parse `git worktree list --porcelain` (passed as $1), printing "<path>\t<branch>"
# for each worktree on a branch, excluding the primary at $2 and detached/bare
# entries. Pure text transform (no git, no cwd), so it is unit-testable.
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
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }
    local primary target any=0 path branch ahead
    primary=$(git rev-parse --show-toplevel 2>/dev/null)
    target=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    while IFS=$'\t' read -r path branch; do
        [ -n "$branch" ] || continue
        ahead=$(git rev-list --count "$target..$branch" 2>/dev/null || echo 0)
        if [ "${ahead:-0}" -gt 0 ]; then printf '%s\t%s\n' "$path" "$branch"; any=1; fi
    done < <(parse_worktrees "$(git worktree list --porcelain 2>/dev/null)" "$primary")
    [ "$any" -eq 1 ] || { msg_wt_landable_none "$target" >&2; return 1; }
}

cmd_verify() {
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }
    [ -f "scripts/run-tests.sh" ] || { msg_wt_no_adapter >&2; return 2; }
    command -v flock >/dev/null 2>&1 || { msg_wt_no_flock "full suite" >&2; return 2; }

    local lock timeout
    lock="$(git rev-parse --git-common-dir 2>/dev/null)/hone-land.lock"
    timeout="${HONE_LAND_LOCK_TIMEOUT:-600}"
    # Land's lock, on purpose: a full suite must never overlap another full
    # suite OR a land's merge/re-verify. One lock makes both exclusions hold.
    exec 9>"$lock" || { msg_wt_lock_unopenable "$lock" >&2; return 2; }
    flock -w "$timeout" 9 || { msg_wt_lock_timeout "$timeout" >&2; return 5; }
    bash scripts/run-tests.sh --all
}

# Classify a branch about to land as IRREVERSIBLE (an effectively irreversible
# or high-blast-radius change), printing one reason line per signal (empty output
# = reversible). Reversibility is the axis: a bad reversible merge is undone with
# `git revert`; a dropped column is not. A project whose changes are all
# reversible is never gated in practice. Signals: destructive SQL in a migration
# or db/ file, a deletion under db/, and any path glob the project lists in the
# committed .hone-irreversible-paths (.hone-consequential-paths is the pre-0.19
# name, still honoured). Git pathspecs do the matching.
land_irreversible() {
    local root="$1" branch="$2" base reasons=""
    base=$(git -C "$root" merge-base HEAD "$branch" 2>/dev/null)
    [ -n "$base" ] || return 0
    if git -C "$root" diff "$base" "$branch" -- db ':(glob)**/migrations/**' 2>/dev/null \
        | grep -E '^\+' | grep -qiE 'DROP[[:space:]]+(TABLE|COLUMN)|TRUNCATE|DELETE[[:space:]]+FROM|ALTER[[:space:]].+DROP'; then
        reasons+="- destructive SQL (DROP/TRUNCATE/DELETE/ALTER…DROP) in a migration or db/ file"$'\n'
    fi
    if git -C "$root" diff --diff-filter=D --name-only "$base" "$branch" -- db 2>/dev/null | grep -q .; then
        reasons+="- a file under db/ is deleted"$'\n'
    fi
    local pf pat
    for pf in .hone-irreversible-paths .hone-consequential-paths; do
        [ -f "$root/$pf" ] || continue
        while IFS= read -r pat; do
            [ -n "$pat" ] || continue
            case "$pat" in \#*) continue ;; esac
            if git -C "$root" diff --name-only "$base" "$branch" -- ":(glob)$pat" 2>/dev/null | grep -q .; then
                reasons+="- touches a path listed in $pf: $pat"$'\n'
            fi
        done < "$root/$pf"
    done
    printf '%s' "$reasons"
}

# Print the branch's diffstat against its merge base, for the authority gate's
# refusal. Capped at 20 file lines plus the summary line: the gate stops an
# unattended run, and the human reading it needs the shape of the change, not
# every file of a large one. $1 = main root, $2 = merge base, $3 = branch.
land_diffstat() {
    local root="$1" base="$2" branch="$3" full total
    [ -n "$base" ] || return 0
    full=$(git -C "$root" diff --stat "$base" "$branch" 2>/dev/null)
    [ -n "$full" ] || return 0
    total=$(printf '%s\n' "$full" | wc -l)
    if [ "$total" -le 21 ]; then
        printf '%s\n' "$full"
        return 0
    fi
    printf '%s\n' "$full" | head -n 20
    printf '... and %d more files\n' "$((total - 21))"
    printf '%s\n' "$full" | tail -n 1
}

# Print non-empty if the branch declares real-environment proof, a `Proof:
# real-environment` trailer in any of its commit messages (the run skill copies
# the Plan's proof class there). A change with no such trailer is
# assertion-class: the gate's suite already proves it, and it is never gated here,
# so a project that never declares real-environment proof is unaffected.
land_proof_required() {
    local root="$1" branch="$2" base
    base=$(git -C "$root" merge-base HEAD "$branch" 2>/dev/null)
    [ -n "$base" ] || return 0
    git -C "$root" log --format=%B "$base..$branch" 2>/dev/null \
        | grep -qiE '^[[:space:]]*Proof:[[:space:]]*real-environment' && echo yes
}

# Print non-empty if the sign-off at .hone-proof/<change> names the commit it
# proved: any hex token of >=7 chars in the file that prefixes the branch tip (so
# `git rev-parse --short` works as well as the full SHA). Binding the sign-off
# to a commit is what stops it going stale: unbound, a sign-off written for one
# commit would silently cover every later commit on the same branch, which is the
# one failure mode a human gate cannot notice from the inside.
land_proof_signoff_names_tip() {
    local file="$1" tip="$2" tok
    for tok in $(tr 'A-Z' 'a-z' < "$file" 2>/dev/null | grep -oE '[0-9a-f]{7,40}'); do
        case "$tip" in "$tok"*) echo yes; return 0 ;; esac
    done
}

cmd_land() {
    local change="${1:-}"
    [ -n "$change" ] || { msg_wt_needs_change land >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }
    command -v flock >/dev/null 2>&1 || { msg_wt_no_flock land >&2; return 2; }

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
    # tree lives inside the lock. Checking outside it would be a TOCTOU race.
    exec 9>"$lock" || { msg_wt_lock_unopenable "$lock" >&2; return 2; }
    flock -w "$timeout" 9 || { msg_wt_lock_timeout "$timeout" >&2; return 5; }

    git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch" || {
        msg_wt_land_no_branch "$branch" >&2; return 2; }
    git -C "$main_root" symbolic-ref -q HEAD >/dev/null || {
        msg_wt_land_detached >&2; return 2; }

    # Authority gate: an IRREVERSIBLE change needs a scoped human grant before
    # it may merge. Capability (guard/bash-guard) is "can the agent act"; this
    # is the separate contract: "may it, for this irreversible act". Checked
    # BEFORE the merge so an ungranted irreversible change never touches the
    # trunk. The grant is scoped (one change), revocable (delete the file),
    # auditable (its text lands in the merge body below), and recoverable (the
    # worktree stays until granted).
    local grant_note="" reasons grant base grant_cmd
    base=$(git -C "$main_root" merge-base HEAD "$branch" 2>/dev/null)
    grant_cmd="bash $HONE_WSH grant $change \"who/why\""
    reasons=$(land_irreversible "$main_root" "$branch")
    if [ -n "$reasons" ]; then
        grant="$main_root/.hone-grant/$change"
        if [ ! -f "$grant" ]; then
            # The refusal carries what the human needs to judge the change: the
            # signals that classified it, a diffstat, and the exact command
            # that shows the whole diff. Reading the branch is otherwise a
            # detour through git plumbing at the moment the run stops.
            msg_wt_land_authority_missing "$branch" "$reasons" \
                "$(land_diffstat "$main_root" "$base" "$branch")" \
                "git -C $main_root diff $base...$branch" \
                "$grant_cmd" >&2
            return 8
        fi
        grant_note=$(cat "$grant" 2>/dev/null)
        # An empty grant authorizes nothing and would leave no audit trail in
        # the merge commit body, so it does not open the gate.
        if ! printf '%s' "$grant_note" | grep -q '[^[:space:]]'; then
            msg_wt_land_grant_empty "$change" "$grant_cmd" >&2
            return 8
        fi
    fi

    # Proof gate: a change whose Plan declared real-environment proof cannot
    # land on the gate's assertion-level suite alone. A green check proves only
    # its assertion, not a browser journey or deployed health. Prove it with a
    # real-environment adapter (scripts/proof.sh) or a human sign-off
    # (.hone-proof/<change>); otherwise land refuses before the merge and
    # escalates. A change with no such declaration is never gated.
    if [ -n "$(land_proof_required "$main_root" "$branch")" ]; then
        local tip signoff="$main_root/.hone-proof/$change" discharged="" attest_cmd
        tip=$(git -C "$main_root" rev-parse "$branch")
        attest_cmd="bash $HONE_WSH attest $change \"what you ran and the outcome\"   (stamps the tip commit)"
        if [ -f "$signoff" ] && [ -n "$(land_proof_signoff_names_tip "$signoff" "$tip")" ]; then
            discharged=yes  # human attested this exact commit
        fi
        if [ -z "$discharged" ]; then
            # Execute the PRIMARY tree's copy of the adapter, the reviewed and
            # already-landed one, so a change cannot ship an always-green
            # proof.sh of its own and wave itself through the gate. The
            # working directory is still the change's WORKTREE when it exists:
            # that tree holds the code under test (the primary tree is still
            # pre-merge here). A proof.sh that first appears inside the change
            # itself does not count until it has landed; that first change
            # needs the human sign-off. Pass the change through, by argument
            # and environment, so the adapter can address its own instance (a
            # per-change port, DB, output dir) instead of guessing.
            local proof_root="$main_root" proof_wt=""
            [ -d "$wt" ] && { proof_root="$wt"; proof_wt="$wt"; }
            if [ -f "$main_root/scripts/proof.sh" ]; then
                if ! ( cd "$proof_root" \
                       && HONE_CHANGE="$change" HONE_BRANCH="$branch" \
                          HONE_WORKTREE="$proof_wt" HONE_MAIN_ROOT="$main_root" \
                          bash "$main_root/scripts/proof.sh" "$change" ); then
                    msg_wt_land_proof_adapter_failed "$branch" >&2
                    return 7
                fi
            elif [ -f "$signoff" ]; then
                msg_wt_land_proof_signoff_stale "$change" "$branch" "$tip" "$attest_cmd" >&2
                return 7
            else
                msg_wt_land_proof_missing "$branch" "$attest_cmd" >&2
                return 7
            fi
        fi
    fi

    local pre; pre=$(git -C "$main_root" rev-parse HEAD)
    local -a merge_args=(merge --no-ff "$branch" -m "Merge branch '$branch'")
    # The grant's text becomes a second commit paragraph. The authorization is
    # then in git history. The first line stays "Merge branch 'hone/<change>'" so
    # the nag's landed-Plan grep still matches.
    [ -n "$grant_note" ] && merge_args+=(-m "Authorized (irreversible change):"$'\n'"$grant_note")
    if ! git -C "$main_root" "${merge_args[@]}" >/dev/null 2>&1; then
        # A conflict means the independence check missed an overlap. Restore the
        # shared tree so the next lander starts clean; the branch stays as
        # evidence to fold in serially. Its own exit code (9), so a caller can
        # tell "fold in serially" from a usage or repo-state error (2).
        git -C "$main_root" merge --abort 2>/dev/null
        msg_wt_land_conflict "$branch" >&2
        return 9
    fi
    if ! ( cd "$main_root" && bash scripts/run-tests.sh --all >/dev/null 2>&1 ); then
        # Green confirms the merge. Red means it regressed the trunk, so roll
        # the merge back and leave the shared tree green for the next lander.
        # The worktree and branch survive for investigation.
        git -C "$main_root" reset --hard "$pre" >/dev/null 2>&1
        msg_wt_land_suite_red "$branch" "" "" >&2
        return 6
    fi
    # Green: the merge is confirmed. Retire the worktree and its branch (cmd_remove
    # runs from the primary tree, so it never refuses "the tree you are in").
    cmd_remove "$wt"
}

# Resolve the main tree's root (the common git dir's parent), the anchor every
# subcommand that must not depend on cwd uses.
main_root_of() {
    git -C "$(git rev-parse --git-common-dir 2>/dev/null)/.." rev-parse --show-toplevel 2>/dev/null
}

# "name <email> | timestamp" for grant/attest stamps.
signer_stamp() {
    printf '%s <%s> | %s' \
        "$(git config user.name 2>/dev/null || echo unknown)" \
        "$(git config user.email 2>/dev/null || echo unknown)" \
        "$(date -Iseconds)"
}

cmd_status() {
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }
    local main_root primary
    main_root=$(main_root_of)
    cd "$main_root" || return 2
    primary=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    msg_status_header "$main_root" "$primary"

    if [ -f ".hone-off" ]; then
        msg_status_hooks_off
    else
        msg_status_hooks_on
    fi

    local a line=""
    for a in run-tests typecheck lint proof; do
        if [ -f "scripts/$a.sh" ]; then line+=" $a=yes"; else line+=" $a=no"; fi
    done
    msg_status_adapters "$line"

    local pf n
    for pf in .hone-durable-paths .hone-irreversible-paths .hone-consequential-paths; do
        [ -f "$pf" ] || continue
        n=$(grep -cvE '^[[:space:]]*(#|$)' "$pf" 2>/dev/null || true)
        if git ls-files --error-unmatch "$pf" >/dev/null 2>&1; then
            msg_status_policy "$pf" "${n:-0}"
        else
            msg_status_policy_uncommitted "$pf" "${n:-0}"
        fi
        [ "$pf" = ".hone-consequential-paths" ] && msg_status_policy_legacy
    done

    local plan change pending=0
    while IFS= read -r plan; do
        [ -f "$(dirname "$plan").md" ] && continue   # a Plan's reference, not a Plan
        change=${plan#.plans/}; change=${change%.md}
        [ -d ".worktrees/$change" ] && continue      # mid-run; its worktree is listed below
        msg_status_plan_pending "$plan"
        pending=$((pending+1))
    done < <(find .plans -type f -name '*.md' 2>/dev/null | sort)
    [ "$pending" -eq 0 ] && msg_status_plans_none

    local path branch any=0
    while IFS=$'\t' read -r path branch; do
        [ -n "$branch" ] || continue
        msg_status_worktree "$path" "$branch"
        any=1
    done < <(parse_worktrees "$(git worktree list --porcelain 2>/dev/null)" "$main_root")
    [ "$any" -eq 0 ] && msg_status_worktrees_none

    local f
    while IFS= read -r f; do
        [ -n "$f" ] && msg_status_grant "$f"
    done < <(find .hone-grant -type f 2>/dev/null | sort)
    while IFS= read -r f; do
        [ -n "$f" ] && msg_status_signoff "$f"
    done < <(find .hone-proof -type f 2>/dev/null | sort)

    local missing_deny
    missing_deny=$(hone_missing_deny_rules "$main_root" "$HONE_PLUGIN_ROOT/templates/settings/deny-rules.txt")
    if [ -z "$missing_deny" ]; then
        msg_status_deny_present
    else
        msg_status_deny_missing "$missing_deny"
    fi
}

cmd_grant() {
    local change="${1:-}"; shift 2>/dev/null || true
    local why="$*"
    if [ -z "$change" ] || [ -z "$why" ]; then
        msg_wt_grant_usage >&2; return 2
    fi
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }
    local main_root; main_root=$(main_root_of)
    local grant="$main_root/.hone-grant/$change"
    mkdir -p "$(dirname "$grant")"
    printf '%s | %s\n' "$(signer_stamp)" "$why" > "$grant"
    msg_wt_grant_recorded "$change"
}

cmd_attest() {
    local change="${1:-}"; shift 2>/dev/null || true
    local what="$*"
    if [ -z "$change" ] || [ -z "$what" ]; then
        msg_wt_attest_usage >&2; return 2
    fi
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }
    local main_root tip
    main_root=$(main_root_of)
    tip=$(git -C "$main_root" rev-parse "hone/$change" 2>/dev/null) || {
        msg_wt_attest_no_branch "$change" >&2; return 2; }
    local signoff="$main_root/.hone-proof/$change"
    mkdir -p "$(dirname "$signoff")"
    printf '%s | %s | %s\n' "$tip" "$(signer_stamp)" "$what" > "$signoff"
    msg_wt_attest_recorded "$change" "${tip:0:7}"
}

cmd_remove() {
    local wt="${1:-}"
    [ -n "$wt" ] || { msg_wt_remove_needs_path >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }

    # The MAIN tree's root (the common git dir's parent), so provenance is stable
    # even when this runs from inside a linked worktree.
    local main_root here
    main_root=$(git -C "$(git rev-parse --git-common-dir 2>/dev/null)/.." rev-parse --show-toplevel 2>/dev/null)
    here=$(git rev-parse --show-toplevel 2>/dev/null)

    case "$wt" in
        "$main_root"/.worktrees/*) : ;;
        *) msg_wt_remove_foreign "$wt" >&2; return 3 ;;
    esac
    [ "$here" = "$wt" ] && { msg_wt_remove_self "$wt" >&2; return 2; }

    # Capture the branch this worktree has checked out BEFORE removing it.
    local branch
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)

    git worktree remove "$wt" || { msg_wt_remove_failed "$wt" >&2; return 2; }
    git worktree prune

    # Land hygiene 1: a landed change's branch goes with its worktree. `-d`
    # (not -D) so an unmerged branch (abandoned or unlanded work) survives as
    # evidence rather than being destroyed.
    case "$branch" in
        hone/*)
            if ! git branch -d "$branch" >/dev/null 2>&1; then
                msg_wt_remove_branch_kept "$branch" >&2
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
        status)   cmd_status "$@" ;;
        grant)    cmd_grant "$@" ;;
        attest)   cmd_attest "$@" ;;
        *) msg_wt_usage >&2; return 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
