#!/bin/bash
# hone worktree helper. The deterministic parts of the run loop's worktree
# handling, kept as a script so the parse is unit-testable. The run skill drives
# the actual `git worktree add` and the build/verify/consolidate steps around it.
#
#   worktree.sh add <change>
#       Create .worktrees/<change> on a new branch hone/<change> off HEAD, and
#       print its absolute path. The worktree+branch ARE the change's claim:
#       creation is atomic (git makes the branch ref), so of two runs racing on
#       one change exactly one wins. Refuses if the worktree or branch already
#       exists: another run owns it, or it is leftover evidence to resume by
#       hand. When the project ships the optional scripts/setup-tree.sh
#       adapter, add then runs it inside the new worktree, so the tree is
#       runnable (dependencies installed) before the first verify. A failed
#       adapter keeps the worktree as evidence and exits 2.
#       Shared mode (see .hone-shared below): add first levels the primary
#       tree with the remote and pushes any local-only commit (a fresh Plan),
#       then claims the change on the remote at refs/hone/claim/<change>. A
#       claim another developer holds refuses with 4 and leaves nothing
#       local behind.
#       A refusal with 4 says what the local claim holds: a file that changed
#       in the last 30 minutes (a run at work), commits or uncommitted files
#       with no such change (work that a dead run left), or nothing at all
#       (safe to remove). Each case names one action for the person.
#       Exit: 0 created · 4 already claimed · 2 usage/not-a-repo/failed ·
#       5 remote contention (shared mode).
#
#   worktree.sh land <change>
#       Land hone/<change> into the primary tree, serialized against every other
#       session that shares it. Takes a flock on <git-common-dir>/hone-land.lock
#       (waits up to HONE_LAND_LOCK_TIMEOUT s, default 600). While it holds the
#       lock, it checks out the primary branch's tip in the change's
#       worktree, merges --no-ff there, and re-runs scripts/run-tests.sh
#       --all and the optional adapters on that merge. On green it
#       fast-forwards the primary branch onto the tested merge commit, then
#       removes the worktree and deletes the branch. When the branch moved
#       during the suite, it merges and verifies again. Any failure leaves
#       the primary tree untouched, and the worktree back on its branch as
#       evidence. Run from the primary tree, after committing in the
#       worktree.
#       Shape gate: some commit on the branch must carry a `Cut: <what>` line
#       in its body, or `Repair: <what>` for a garden repair. Without one land
#       refuses BEFORE every other gate (exit 2), because the fix amends a
#       commit, and that moves the tip a proof sign-off names.
#       Authority gate: an IRREVERSIBLE change (destructive SQL, a db/ deletion,
#       or a .hone-irreversible-paths match) may not merge without a scoped
#       grant at .hone-grant/<change>. Without it land refuses BEFORE the merge
#       and keeps the worktree as evidence. The grant's text goes into the
#       merge commit body, so the authorization lives in durable history rather
#       than a chat. A green land then deletes the spent grant file: a grant
#       is not pinned to a commit, so a leftover one would open the gate for
#       a LATER change that reuses the slug.
#       Proof gate: a change whose Plan declared real-environment proof (a
#       `Proof: real-environment` trailer on a branch commit) may not land on
#       the test suite alone. Satisfy it either with a green scripts/proof.sh
#       or with a human sign-off at .hone-proof/<change>. land runs the PRIMARY
#       tree's reviewed copy of proof.sh, from the change's WORKTREE, since
#       that tree holds the code under test. Running the change's own copy
#       would let it ship a green stub. The adapter gets HONE_CHANGE/
#       HONE_BRANCH/HONE_WORKTREE/HONE_MAIN_ROOT in its environment. The
#       sign-off names the commit it proved, so a sign-off cannot outlive the
#       code it attested. A sign-off that discharged the gate goes into the
#       merge commit body like a grant, and a green land deletes the spent
#       file. Else land refuses BEFORE the merge. A committed
#       .hone-proof-always marker widens the gate to EVERY change, trailer or
#       not. With the marker present and no scripts/proof.sh, land refuses (7)
#       rather than proving nothing.
#       A change that edits scripts/proof.sh, or a probe under
#       scripts/proof-probes/ that already exists, opens the gate on the file
#       change alone. It needs no trailer and no marker, and only a sign-off
#       discharges it: land holds the copy such a change replaces, so no
#       automatic route can judge it. Adding a NEW probe does not open it.
#       When the primary branch changed a lockfile since the cut and the
#       project ships scripts/setup-tree.sh, land runs that adapter in the
#       worktree BEFORE the suite on the merge. Without it, the suite runs
#       on the stale install and reds, though the change is sound. A red
#       adapter there fails the land like a red suite (exit 6). When the
#       change itself touched a lockfile, land runs the adapter again in
#       the primary tree after the fast-forward. The merge stands by then,
#       so a red run there is a warning.
#       A land whose worktree is gone cuts it again from the branch first.
#       On success it prints a receipt on stdout: the merge commit, the green
#       suite on it, and the removed worktree and branch. When the change
#       touched a lockfile, the receipt also names it, and asks for a
#       reinstall in the primary tree when no setup-tree adapter ran there.
#       Shared mode: land levels the primary tree with the remote first, so
#       the merge goes on top of the team's latest. After the green suite it
#       pushes the primary branch. Git rejects that push when the remote moved
#       while the suite ran, so land undoes its fast-forward, levels again,
#       and redoes merge and suite, up to HONE_LAND_RETRIES times (default 3).
#       Nothing untested ever reaches the remote. On success it releases the
#       claim. Exhausted retries exit 5 with nothing published. A push the
#       host refused (a protected branch) is exit 2, no retry: land tells the
#       two apart by fetching again after a rejection.
#       Exit: 0 landed · 2 usage/not-a-repo/detached/push refused/caller in
#       the worktree/dirty worktree/files in the way · 5 lock timeout, or the
#       branch or remote moved on every attempt · 6 red on the merge, or a git
#       hook refused the merge commit · 7 real-environment proof missing · 8
#       ungranted irreversible change · 9 merge conflict (paths named).
#
#   worktree.sh review-scope <change>
#       Print how deep the change's review must go: `full`, or `docs-only`
#       when the diff against the merge base touches nothing outside docs/
#       and .plans/. A committed .hone-review-always lists path globs that
#       force `full` even inside docs/. Anything it cannot classify is
#       `full`. Exit: 0 printed · 2 usage/not-a-repo/no such branch.
#
#   worktree.sh governed <change>
#       Print the Decisions and Notes about the code that the change touched,
#       one path per line. A document counts when a path on its `Governs:`
#       line is a changed file or a directory above one. A Note also counts
#       by its name: docs/notes/<area>.md is about src/<area>/. The answer
#       reads the change's worktree, committed or not, so consolidate can ask
#       before the commit. With no worktree it reads the branch's diff and the
#       primary tree's documents, so it misses a Governs: line that only the
#       branch carries. The loop hands these documents to the
#       consolidate-critic. A change can make a sentence false in a document
#       that it never opened, and nobody reads a document that nothing puts
#       in front of them. Exit: 0 printed, or nothing to print · 2
#       usage/not-a-repo/no such branch.
#
#   worktree.sh verify
#       Run the full suite (scripts/run-tests.sh --all) in the current tree,
#       serialized under the SAME lock as land. e2e tiers are load-sensitive:
#       two concurrent full suites poison each other's signal (phantom flakes),
#       and a suite racing a land's re-verify produces spurious reds. So
#       every full-suite run shares the one lock. This is the sanctioned way to
#       run --all by hand. Never invoke the adapter bare for a full run. The
#       fast unit tier needs no lock and no wrapper. Exit: the adapter's exit ·
#       2 usage/not-a-repo/no-adapter · 5 lock timeout.
#
#   worktree.sh landable
#       Print "<worktree-path>\t<branch>" for every linked worktree on a branch
#       ahead of the current (primary) branch: the fan-in set for land. Excludes
#       the primary, detached-HEAD, and bare entries. Exit 0 if any, 1 if none,
#       2 if not a git repo.
#
#   worktree.sh landed <change>
#       Answer "has <change> fully landed?" from repo artifacts, printing one
#       word: `landed` (exit 0) or `pending` (exit 1). Landed means all of:
#       a "Merge branch 'hone/<change>'" commit reachable from the primary
#       HEAD, no hone/<change> branch, no .worktrees/<change>, and no
#       .plans/<change>.md at HEAD. The proof and authority gates run before
#       the merge, so the merge commit's existence implies both gates passed.
#       This is the predicate an orchestrator (the MAIN session of
#       `--all` under herdr) polls before it starts a dependent Plan or closes
#       a SUB tab.
#       It reads the repository, never a subagent's claim that it finished.
#       Shared mode: the questions go to the remote primary branch after a
#       fetch, and a claim still on the remote reads as pending. So "landed"
#       means landed for the team, from any developer's clone.
#       Exit: 0 landed · 1 pending · 2 usage/not-a-repo.
#
#   worktree.sh sync
#       Shared mode only. Level the primary tree with the remote primary
#       branch both ways: fetch, then fast-forward or rebase local-only
#       commits on top, then push them. The plan skill runs it after
#       committing a Plan, so the Plan reaches the team's queue. A human runs
#       it to catch up. Under the land lock. Exit: 0 level · 2 not shared,
#       no such remote, dirty tree, fetch failed, or rebase conflict
#       (aborted) · 5 the remote moved on every push attempt.
#
#   Shared mode. A committed .hone-shared marker turns it on. Its first
#   non-comment line names the remote, and a blank file means origin. The
#   primary branch then belongs to the team on that remote: add claims
#   there, land pushes there, and landed and sync read from there. Without
#   the marker none of this runs, so a solo repository with a backup remote
#   never starts pushing on an upgrade. The remote must accept pushes to
#   refs/hone/*, which GitHub, GitLab, and Gitea do.
#
#   worktree.sh status
#       One-screen state of the control surface: hooks on/off, adapters
#       present, policy files (and whether they are committed), pending Plans,
#       worktrees in flight, other developers' claims on the remote (shared
#       mode), grants and proof sign-offs. It also says whether
#       the settings.json deny rules are present. Read-only, and always exit 0
#       in a git repo.
#
#   worktree.sh grant <change> "who/why"
#       Record the authority grant for one irreversible change at
#       .hone-grant/<change>, stamped with the git user and the current time.
#       A person and the agent both run it, and the stamp says which (see
#       signer_stamp). It is the only route to the file: both guards deny a
#       raw write, because the stamp lives here.
#
#   worktree.sh attest <change> "what you ran"
#       Record the real-environment sign-off at .hone-proof/<change>, stamped
#       with the branch tip it proves (so it stops counting after new commits),
#       the git user, and the time. The human's act alone: the bash-guard
#       denies the agent this helper, and the agent hands over the check's
#       output instead. Same sole-route rule as grant. Record only a check
#       that actually ran.
#
#   worktree.sh release <change>
#       Shared mode only. Delete the change's claim from the remote by hand,
#       for a claim whose worktree is already gone (an abandoned change, a
#       crashed run). remove does the same with the worktree. Exit: 0
#       released · 2 not shared, no such remote, or the delete failed.
#
#   worktree.sh remove <worktree-path | change>
#       Provenance-guarded cleanup. Removes the worktree ONLY if hone created it
#       (path under the main tree's .worktrees/). It leaves anything elsewhere
#       for its owner. Prunes stale registrations after. Refuses to remove the
#       tree you are standing in. Then finishes the land's hygiene. It deletes
#       the worktree's hone/* branch iff it is fully merged (`git branch -d`),
#       and an unmerged branch is evidence and stays, with a note. It also
#       removes now-empty parent dirs under .worktrees/ that a nested slug
#       leaves behind. In shared mode it also releases the change's claim on
#       the remote. Exit: 0 removed · 2 usage/not-a-repo/failed/self ·
#       3 left in place (not hone's to remove).
#
# Runs relative to the project root (git toplevel, else CLAUDE_PROJECT_DIR, else
# cwd, matching the hooks).

set -uo pipefail

# pipefail makes SIGPIPE observable, and `grep -q` provokes it. The grep exits
# on its first match. The writer then takes SIGPIPE (exit 141) on its next
# write. pipefail reports the 141 as the pipeline's status, so a condition
# reads failure exactly when a match exists. That made `landed` print pending
# for a landed change, and it can silence a land gate. So in this file, no
# pipeline whose STATUS is tested may end in a reader that quits early
# (`grep -q`, `head`). Test `[ -n "$(...)" ]` on captured output instead, or
# keep a final grep that reads its whole input and sends its print to
# /dev/null. A pipeline whose status nothing reads (a capture, a display cap)
# may keep `head`.

# This script's own absolute path, for remedy messages. The human runs the
# grant/attest helpers in their own terminal, where ${CLAUDE_PLUGIN_ROOT} is
# not set, so a bare "worktree.sh ..." would fail.
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

    # Anchor to the MAIN tree, not cwd. An orchestrator's shell cwd may sit
    # inside a sibling change's linked worktree. That would nest the new
    # worktree under it, and branch it off that sibling's unlanded HEAD. `git -C
    # "$main_root" ... HEAD` resolves both the path and the base in the primary
    # checkout. Same provenance anchor cmd_remove uses.
    local main_root
    main_root=$(git -C "$(git rev-parse --git-common-dir 2>/dev/null)/.." rev-parse --show-toplevel 2>/dev/null)

    local path="$main_root/.worktrees/$change"
    local branch="hone/$change"
    # The worktree/branch is the change's claim. "Already exists" is exit 4
    # (claimed), distinct from a real failure (2), so a `run` can tell "another
    # run owns this, skip it" from "something broke".
    # The refusal says what the claim holds. A run that stops on a claim
    # reports to a person, and "another run owns it, or it is leftover" leaves
    # that person to find out which. A file that changed in the last 30
    # minutes is the sign of a run at work. Without one, the commits and the
    # uncommitted files say whether the dead run left work behind.
    local ahead dirty
    ahead=$(git -C "$main_root" rev-list --count "HEAD..$branch" 2>/dev/null || echo 0)
    if [ -e "$path" ]; then
        if [ -n "$(find "$path" \( -name .git -o -name node_modules -o -name .venv \) -prune \
                        -o -type f -mmin -30 -print 2>/dev/null | head -1)" ]; then
            msg_wt_add_claimed_live "$path" "bash $HONE_WSH landed $change" >&2
            return 4
        fi
        dirty=$(git -C "$path" status --porcelain 2>/dev/null | grep -c . || true)
        if [ "${ahead:-0}" -eq 0 ] && [ "${dirty:-0}" -eq 0 ]; then
            msg_wt_add_claimed_empty "$path" "bash $HONE_WSH remove $path" >&2
        else
            msg_wt_add_claimed_work "$path" "${ahead:-0}" "${dirty:-0}" >&2
        fi
        return 4
    fi
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        msg_wt_add_branch_claimed "$branch" "${ahead:-0}" "$(git -C "$main_root" rev-parse --abbrev-ref HEAD 2>/dev/null)" >&2
        return 4
    fi

    # Shared mode: cut the worktree from the team's primary branch, not a
    # stale local one, and publish any local-only Plan commit while at it.
    # Under the land lock, because sync moves the primary HEAD.
    local remote="" primary
    remote=$(shared_remote_checked "$main_root") || { [ $? -eq 2 ] && return 2; }
    if [ -n "$remote" ]; then
        command -v flock >/dev/null 2>&1 || { msg_wt_no_flock add >&2; return 2; }
        primary=$(git -C "$main_root" symbolic-ref -q --short HEAD) || {
            msg_wt_land_detached >&2; return 2; }
        exec 9>"$(git -C "$main_root" rev-parse --git-common-dir)/hone-land.lock" || return 2
        flock -w "${HONE_LAND_LOCK_TIMEOUT:-600}" 9 || {
            msg_wt_lock_timeout "${HONE_LAND_LOCK_TIMEOUT:-600}" >&2; return 5; }
        shared_push_primary "$main_root" "$remote" "$primary" || return $?
        exec 9>&-
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
    # Shared mode: the claim lives on the remote (see shared_claim). A refused
    # claim tears the local worktree down again, so nothing here says "mine".
    if [ -n "$remote" ]; then
        local rc=0
        shared_claim "$main_root" "$remote" "$change" || rc=$?
        if [ "$rc" -ne 0 ]; then
            git -C "$main_root" worktree remove --force "$path" >/dev/null 2>&1
            git -C "$main_root" branch -D "$branch" >/dev/null 2>&1
            [ "$rc" -eq 4 ] && msg_wt_add_remote_claimed "$change" "$remote" >&2
            return "$rc"
        fi
    fi
    # A fresh worktree shares no installed dependencies with the primary tree,
    # so its first verify can red for an environment reason that reads like a
    # real break. The optional setup-tree adapter is the project's "make this
    # tree runnable" step. Run the worktree's own copy: the tree was just cut
    # from HEAD, so it is HEAD's copy. stdout stays the worktree path alone
    # (the caller captures it), so the adapter's output is buffered and only a
    # failure prints its tail. On failure the claim stands and the worktree
    # stays as evidence: the caller fixes the install and resumes by hand.
    if [ -f "$path/scripts/setup-tree.sh" ]; then
        local setup_out
        if ! setup_out=$( (cd "$path" && bash scripts/setup-tree.sh) 2>&1 ); then
            msg_wt_add_setup_tree_failed "$path" "$(printf '%s\n' "$setup_out" | tail -n 20)" >&2
            return 2
        fi
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

# Classify how deep a change's judgment review must go, printing one word:
# `full` (the default) or `docs-only`.
#
# `/code-review` reviews code. A diff
# that changes no executable file gives it nothing to read. So the loop skips
# it for such a change, and the consolidate-critic stays that change's judgment
# check. A garden pass that only deletes stale prose is the case this exists
# for.
#
# The classification is mechanical on purpose. "Is this change small enough to
# skip its review?" is exactly the judgment call an unattended loop must not
# make about itself, so the loop reads this word and never its own opinion. The
# rule is therefore narrow: every changed path sits under docs/ or .plans/.
# Size is NOT a signal, because a five-line change to an auth path needs the
# full review. Neither is "tests only", because a weakened test is one of the
# things review exists to catch. Anything this cannot classify is `full`.
#
# .hone-review-always lists path globs that force `full` even inside docs/, for
# prose a project's own tooling executes (a prompt, a policy file). Git
# pathspecs do the matching, as in land_irreversible.
#
# Takes the same (root, base, branch) triple the land helpers take.
review_scope() {
    local root="$1" base="$2" branch="$3" files pat
    [ -n "$base" ] || { printf 'full\n'; return 0; }
    # --no-renames on purpose: with rename detection a move from src/ into docs/
    # prints only the new path, and the diff would read as docs-only. Without it
    # the same move prints the deletion and the addition, so src/ still shows.
    files=$(git -C "$root" diff --no-renames --name-only "$base" "$branch" 2>/dev/null)
    [ -n "$files" ] || { printf 'full\n'; return 0; }
    if printf '%s\n' "$files" | grep -vE '^(docs|\.plans)/' >/dev/null; then
        printf 'full\n'; return 0
    fi
    if [ -f "$root/.hone-review-always" ]; then
        while IFS= read -r pat; do
            [ -n "$pat" ] || continue
            case "$pat" in \#*) continue ;; esac
            if [ -n "$(git -C "$root" diff --name-only "$base" "$branch" -- ":(glob)$pat" 2>/dev/null)" ]; then
                printf 'full\n'; return 0
            fi
        done < "$root/.hone-review-always"
    fi
    printf 'docs-only\n'
}

cmd_review_scope() {
    local change="${1:-}"
    [ -n "$change" ] || { msg_wt_needs_change review-scope >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }

    local common_dir main_root branch base
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    main_root=$(git -C "$common_dir/.." rev-parse --show-toplevel 2>/dev/null)
    branch="hone/$change"
    git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch" || {
        msg_wt_review_scope_no_branch "$branch" >&2; return 2; }
    # Resolve HEAD in the MAIN tree, as cmd_land does: the caller's shell may sit
    # inside the change's own worktree, where HEAD is the branch itself.
    base=$(git -C "$main_root" merge-base HEAD "$branch" 2>/dev/null)
    review_scope "$main_root" "$base" "$branch"
}

cmd_governed() {
    local change="${1:-}"
    [ -n "$change" ] || { msg_wt_needs_change governed >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }

    local common_dir main_root branch wt base tree changed doc path hit
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    main_root=$(git -C "$common_dir/.." rev-parse --show-toplevel 2>/dev/null)
    branch="hone/$change"
    wt="$main_root/.worktrees/$change"
    git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch" || {
        msg_wt_governed_no_branch "$branch" >&2; return 2; }
    base=$(git -C "$main_root" merge-base HEAD "$branch" 2>/dev/null)
    [ -n "$base" ] || return 0
    # Consolidate runs before the commit, so the worktree is the change. With
    # no worktree the branch is all that is left to read.
    if [ -d "$wt" ]; then
        tree="$wt"
        changed=$( { git -C "$wt" diff --no-renames --name-only "$base"
                     git -C "$wt" ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
    else
        tree="$main_root"
        changed=$(git -C "$main_root" diff --no-renames --name-only "$base" "$branch" 2>/dev/null)
    fi
    [ -n "$changed" ] || return 0

    # One changed file under PATH (a file, or a directory above the file)?
    governed_touched() {
        local f want="${1%/}"
        while IFS= read -r f; do
            case "$f" in "$want"|"$want"/*) return 0 ;; esac
        done <<<"$changed"
        return 1
    }
    while IFS= read -r doc; do
        [ -n "$doc" ] || continue
        hit=""
        while IFS= read -r path; do
            [ -n "$path" ] && governed_touched "$path" && { hit=yes; break; }
        done < <(hone_governs_paths "$tree/$doc" "$tree")
        # A Note is flat, docs/notes/<area>.md, as the nag reads it.
        if [ -z "$hit" ] && [ "$(dirname "$doc")" = docs/notes ]; then
            governed_touched "src/$(basename "$doc" .md)" && hit=yes
        fi
        [ -z "$hit" ] || printf '%s\n' "$doc"
    done < <(cd "$tree" && find docs/decisions docs/notes -type f -name '*.md' 2>/dev/null | sort)
    return 0
}

# Classify a branch about to land as IRREVERSIBLE (an effectively irreversible
# or high-blast-radius change), printing one reason line per signal (empty output
# = reversible). Reversibility is the axis: `git revert` undoes a bad reversible
# merge, and nothing undoes a dropped column. In practice this gate never fires
# for a project whose changes are all reversible. Signals: destructive SQL in a
# migration or db/ file, a deletion under db/, and any path glob the project
# lists in the committed .hone-irreversible-paths. (.hone-consequential-paths
# is the pre-0.19 name, still honoured.) Git pathspecs do the matching.
#
# Every land helper takes the same three leading arguments, (root, base,
# branch), because cmd_land resolves the merge base once and passes it down. The
# base was a separate `git merge-base` call in four helpers before.
land_irreversible() {
    local root="$1" base="$2" branch="$3" reasons=""
    [ -n "$base" ] || return 0
    # The final grep runs without -q on purpose. With -q it quit on its first
    # match, the diff writer took SIGPIPE on a migration larger than the pipe,
    # and this gate stayed quiet on exactly the diff that carried a real DROP.
    #
    # The signal carries the matched statements with their files, up to ten.
    # Whoever records the grant then judges the statement, not a file name.
    # A table rewrite (create, copy, drop, rename) is the common case, and it
    # loses data exactly when the copy leaves a column out.
    local sql
    sql=$(git -C "$root" diff -U0 "$base" "$branch" -- db ':(glob)**/migrations/**' 2>/dev/null \
        | awk '
            /^\+\+\+ / { f = substr($0, 7); next }
            /^\+/ {
                line = substr($0, 2); u = toupper(line)
                if (u ~ /DROP[ \t]+(TABLE|COLUMN)|TRUNCATE|DELETE[ \t]+FROM|ALTER[ \t].*DROP/) {
                    n++
                    if (n <= 10) print "    " f ": " line
                }
            }
            END { if (n > 10) print "    ... and " n - 10 " more" }')
    if [ -n "$sql" ]; then
        reasons+="- destructive SQL (DROP/TRUNCATE/DELETE/ALTER...DROP) in a migration or db/ file:"$'\n'"$sql"$'\n'
    fi
    if [ -n "$(git -C "$root" diff --diff-filter=D --name-only "$base" "$branch" -- db 2>/dev/null)" ]; then
        reasons+="- a file under db/ is deleted"$'\n'
    fi
    local pf pat
    for pf in .hone-irreversible-paths .hone-consequential-paths; do
        [ -f "$root/$pf" ] || continue
        while IFS= read -r pat; do
            [ -n "$pat" ] || continue
            case "$pat" in \#*) continue ;; esac
            if [ -n "$(git -C "$root" diff --name-only "$base" "$branch" -- ":(glob)$pat" 2>/dev/null)" ]; then
                reasons+="- touches a path listed in $pf: $pat"$'\n'
            fi
        done < "$root/$pf"
    done
    printf '%s' "$reasons"
}

# Print the branch's diffstat against its merge base, for the authority gate's
# refusal. Capped at 20 file lines plus the summary line. The gate stops an
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

# The ONE parser for the `Proof: real-environment` trailer, which the run skill
# copies from the Plan into a branch commit. It finds the first such line in the
# branch's commits and prints what the trailer declares: the check the human
# must run. `plan` makes that description mandatory, so the gate can print the
# exact check instead of sending the human back to the Plan.
#
# Exit 0 means the branch declares the trailer, and 1 means it does not. So a
# bare trailer (an older Plan, no description) is exit 0 with empty output.
# Callers must read the exit code, never the emptiness of the output.
#
# The prefix and the separator come off case-insensitively (`sed s///I`). The
# separator may be an em dash, an en dash, one or more hyphens, or nothing
# at all. A single parser is why `PROOF: REAL-ENVIRONMENT — x` no longer prints
# its own prefix back, and why `-- x` no longer keeps a stray dash.
land_proof_trailer() {
    local root="$1" base="$2" branch="$3" line
    [ -n "$base" ] || return 1
    line=$(git -C "$root" log --format=%B "$base..$branch" 2>/dev/null \
        | grep -iE '^[[:space:]]*Proof:[[:space:]]*real-environment' \
        | head -n 1)
    [ -n "$line" ] || return 1
    printf '%s' "$line" | sed -E \
        -e 's/^[[:space:]]*Proof:[[:space:]]*real-environment[[:space:]]*(—|–|-+)?[[:space:]]*//I' \
        -e 's/[[:space:]]+$//'
}

# Print non-empty if the branch declares real-environment proof. A change with
# no such trailer is assertion-class: the gate's suite already proves it, and
# this gate never fires for it. So a project that never declares
# real-environment proof is unaffected.
land_proof_required() {
    land_proof_trailer "$1" "$2" "$3" >/dev/null && echo yes
}

# Print the change name when the branch rewrites the proof HARNESS: the adapter
# scripts/proof.sh, or a probe under scripts/proof-probes/ that already exists.
# land runs the PRIMARY tree's copy, which for such a change is the copy the
# change replaces, so no automatic route exists. The caller runs the branch's own
# adapter from the worktree and attests with its output.
#
# A change that only ADDS a new probe is not that case, and does not gate here.
# The adapter decides what a green run means, and it stays the reviewed copy. A
# new probe only adds a check for the one change that ships it, exactly as that
# change ships its own tests. /code-review reads it in the same diff. Gating
# an added probe cost a sign-off on every proof-carrying change in a project
# whose adapter asks each change for its own probe. That is the shape
# templates/proof/README.md recommends. An edit to a probe that already exists
# still gates: that probe guards a change that landed before this one.
#
# It prints the commands the human runs, one per line, and prints nothing when
# the change leaves the harness alone. An edited probe usually serves another,
# landed change, and an adapter that picks its probe by change name finds no
# probe under this change's name. So each edited probe gets the command under
# its own name. A rewritten adapter, or a deleted probe, gets the change's own.
land_proof_bootstrap() {
    local root="$1" base="$2" branch="$3" change="$4" cmds="" probe
    [ -n "$base" ] || return 0
    if [ -n "$(git -C "$root" diff --name-only "$base" "$branch" \
        -- scripts/proof.sh 2>/dev/null)" ] \
       || [ -n "$(git -C "$root" diff --name-only --diff-filter=D "$base" "$branch" \
        -- scripts/proof-probes 2>/dev/null)" ]; then
        cmds="bash scripts/proof.sh $change"
    fi
    # Every status except A (added), C (copied), and D (above): a probe that
    # already exists, modified, renamed, or type-changed.
    # A probe is a .sh file. Any other file there (a fixture, a note) names
    # no probe, so its edit gets the change's own command.
    while IFS= read -r probe; do
        [ -n "$probe" ] || continue
        probe=${probe#scripts/proof-probes/}
        case "$probe" in
            *.sh) probe=${probe%.sh} ;;
            *)    probe=$change ;;
        esac
        case $'\n'"$cmds"$'\n' in
            *$'\n'"bash scripts/proof.sh $probe"$'\n'*) continue ;;
        esac
        cmds="$cmds${cmds:+$'\n'}bash scripts/proof.sh $probe"
    done < <(git -C "$root" diff --name-only --diff-filter=MRTUXB "$base" "$branch" \
        -- scripts/proof-probes 2>/dev/null)
    printf '%s' "$cmds"
}

# Print non-empty if the sign-off at .hone-proof/<change> names the commit it
# proved. Naming means any hex token of >=7 chars in the file that prefixes the
# branch tip (so `git rev-parse --short` works as well as the full SHA).
# Binding the sign-off to a commit is what stops it going stale. Unbound, a
# sign-off written for one commit would silently cover every later commit on
# the same branch. That is the one failure mode a human gate cannot notice from
# the inside.
land_proof_signoff_names_tip() {
    local file="$1" tip="$2" tok
    for tok in $(tr 'A-Z' 'a-z' < "$file" 2>/dev/null | grep -oE '[0-9a-f]{7,40}'); do
        case "$tip" in "$tok"*) echo yes; return 0 ;; esac
    done
}

# Delete the record at $dir/$change and the empty parent dirs a nested slug
# leaves behind, up to (not including) $dir. Print the record's repo-relative
# path when a file was deleted, for the land receipt.
#
# Only a GREEN land calls this. cmd_remove does not: remove is also the
# abandon path, and an abandoned change keeps its records for the retry. A
# spent grant is the dangerous leftover. It is not pinned to a commit, so it
# would open the authority gate for a later change that reuses the slug. A
# spent sign-off is pinned and merely accumulates.
land_consume_record() {
    local dir="$1" change="$2" f parent
    f="$dir/$change"
    [ -f "$f" ] || return 0
    rm -f "$f"
    parent=$(dirname "$f")
    while [ "$parent" != "$dir" ] && [ "$parent" != "/" ]; do
        rmdir "$parent" 2>/dev/null || break
        parent=$(dirname "$parent")
    done
    printf '%s/%s' "$(basename "$dir")" "$change"
}

# Print one "- <tier>" line for every tier the suite reported as empty. The
# adapter contract asks for a `hone tier: <name> ran=<count>` line per tier
# (templates/run-tests/README.md). A tier that matches no test still exits 0,
# so a green suite can cover nothing and nobody sees it. An older adapter
# prints no such lines, and this prints nothing.
land_zero_tiers() {
    awk '
        /hone tier:/ {
            name = ""; zero = 0
            for (i = 1; i <= NF; i++) {
                if ($i == "tier:" && i < NF) name = $(i+1)
                if ($i == "ran=0") zero = 1
            }
            if (name != "" && zero) print "- " name
        }
    ' "$1" 2>/dev/null
}

# Print every lockfile the merged diff touched, one path per line (empty output
# = none). A landed lockfile leaves the primary tree's installed packages behind
# the manifest: the merge updates the file, and nothing reinstalls. A consumer
# repo ran its formatter from a 75-minute-old install against a landed newer
# config because nobody named the reinstall step. Matching is by file name, so a
# lockfile in a subdirectory of a monorepo counts too.
land_lockfiles() {
    local root="$1" base="$2" branch="$3"
    [ -n "$base" ] || return 0
    git -C "$root" diff --name-only "$base" "$branch" 2>/dev/null \
        | grep -E '(^|/)(bun\.lock|bun\.lockb|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|uv\.lock|poetry\.lock|Cargo\.lock|Gemfile\.lock|composer\.lock|go\.sum)$'
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
    # A green land removes the worktree. A caller whose shell stands inside
    # it is left in a deleted directory, and every later command in that
    # shell fails. main() already moved this process to the tree root, so
    # the caller's own directory comes from WT_CALLER_PWD.
    if [ -d "$wt" ] && [ -n "${WT_CALLER_PWD:-}" ]; then
        local caller_dir wt_dir
        caller_dir=$(cd "$WT_CALLER_PWD" 2>/dev/null && pwd -P)
        wt_dir=$(cd "$wt" 2>/dev/null && pwd -P)
        case "$caller_dir/" in
            "$wt_dir"/*) msg_wt_land_from_worktree "$main_root" "bash $HONE_WSH land $change" >&2; return 2 ;;
        esac
    fi

    exec 9>"$lock" || { msg_wt_lock_unopenable "$lock" >&2; return 2; }
    flock -w "$timeout" 9 || { msg_wt_lock_timeout "$timeout" >&2; return 5; }

    git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch" || {
        msg_wt_land_no_branch "$branch" >&2; return 2; }
    git -C "$main_root" symbolic-ref -q HEAD >/dev/null || {
        msg_wt_land_detached >&2; return 2; }

    # Shape gate: the change says what it removed. Every cycle removes
    # something, and the `Cut:` line in a commit body is the record of it. A
    # garden repair removes nothing and carries `Repair:` instead. The run and
    # garden skills ask for the line, and this gate is what holds them to it.
    # It comes first, because an amended commit moves the tip, and a proof
    # sign-off names the tip.
    local base
    base=$(git -C "$main_root" merge-base HEAD "$branch" 2>/dev/null)
    # A line that copies the placeholder of the refusal, or that says
    # "nothing" and gives no reason, records nothing, so it does not count.
    if [ -n "$(git -C "$main_root" rev-list "$base..$branch" 2>/dev/null)" ] \
       && ! git -C "$main_root" log --format=%B "$base..$branch" \
            | grep -E '^(Cut|Repair): +[^[:space:]<]' \
            | grep -viE '^Cut: +nothing[[:space:][:punct:]]*$' >/dev/null; then
        msg_wt_land_no_cut_line "$branch" "$wt" >&2
        return 2
    fi

    # Authority gate: an IRREVERSIBLE change needs a scoped human grant before
    # it may merge. Capability (guard/bash-guard) is "can the agent act". This
    # is the separate contract: "may it, for this irreversible act". land
    # checks this BEFORE the merge, so an ungranted irreversible change never
    # touches the trunk. The grant is scoped (one change), revocable (delete
    # the file), auditable (its text lands in the merge body below), and
    # recoverable (the worktree stays until granted).
    local grant_note="" signoff_note="" reasons grant grant_cmd
    grant_cmd="bash $HONE_WSH grant $change \"$(hone_msg_grant_why)\""
    reasons=$(land_irreversible "$main_root" "$base" "$branch")
    if [ -n "$reasons" ]; then
        grant="$main_root/.hone-grant/$change"
        if [ ! -f "$grant" ]; then
            # The refusal carries what the human needs to judge the change.
            # That is the signals that classified it, a diffstat, and the exact
            # command that shows the whole diff. Reading the branch is
            # otherwise a detour through git plumbing at the moment the run
            # stops.
            msg_wt_land_authority_missing "$branch" "$reasons" \
                "$(land_diffstat "$main_root" "$base" "$branch")" \
                "git -C $main_root diff $base...$branch" \
                "$grant_cmd" >&2
            return 8
        fi
        grant_note=$(cat "$grant" 2>/dev/null)
        # An empty grant authorizes nothing and would leave no audit trail in
        # the merge commit body, so it does not open the gate.
        if ! printf '%s' "$grant_note" | grep '[^[:space:]]' >/dev/null; then
            msg_wt_land_grant_empty "$change" "$grant_cmd" >&2
            return 8
        fi
    fi

    # Proof gate: a change whose Plan declared real-environment proof cannot
    # land on the gate's assertion-level suite alone. A green check proves only
    # its assertion, not a browser journey or deployed health. Prove it with a
    # real-environment adapter (scripts/proof.sh) or a human sign-off
    # (.hone-proof/<change>). Otherwise land refuses before the merge and
    # escalates. This gate never fires for a change with no such declaration.
    #
    # A committed .hone-proof-always marker widens that to every change. The
    # project has an adapter and wants it run each time, so land still proves
    # a change that forgot its trailer. Existence is the whole switch, and
    # the contents are free for a comment.
    #
    # A change to the adapter ITSELF gates on the file change, with no trailer
    # and no marker needed. The adapter defines the verdict this gate trusts.
    # So the copy a change rewrites must not judge that change, and the change
    # must not merge unseen either. Gating on the trailer alone left that
    # hole open. A branch that weakened scripts/proof.sh and declared nothing
    # never reached the bootstrap check below, and merged with no human in the
    # loop.
    local proof_always=""
    [ -f "$main_root/.hone-proof-always" ] && proof_always=yes
    # Classify the bootstrap case here, OUTSIDE the condition. It is now
    # one of the three things that open the gate, not a branch taken
    # inside it.
    local bootstrap
    bootstrap=$(land_proof_bootstrap "$main_root" "$base" "$branch" "$change")
    if [ -n "$proof_always" ] || [ -n "$bootstrap" ] \
       || [ -n "$(land_proof_required "$main_root" "$base" "$branch")" ]; then
        local tip signoff="$main_root/.hone-proof/$change" discharged="" attest_cmd check
        tip=$(git -C "$main_root" rev-parse "$branch")
        attest_cmd="bash $HONE_WSH attest $change \"$(hone_msg_attest_what_full)\"   (stamps the tip commit)"
        if [ -f "$signoff" ] && [ -n "$(land_proof_signoff_names_tip "$signoff" "$tip")" ]; then
            discharged=yes  # human attested this exact commit
            # The green land below deletes the spent sign-off, so its text
            # must survive in the merge commit body, like a grant's.
            signoff_note=$(cat "$signoff" 2>/dev/null)
        fi
        if [ -z "$discharged" ]; then
            # Execute the PRIMARY tree's copy of the adapter, the reviewed and
            # already-landed one. So a change cannot ship an always-green
            # proof.sh of its own and pass the gate with it. The
            # working directory is still the change's WORKTREE when it exists:
            # that tree holds the code under test (the primary tree is still
            # pre-merge here). A proof.sh that first appears inside the change
            # itself does not count until it has landed. That first change
            # needs the human sign-off. Pass the change through, by argument
            # and environment, so the adapter can address its own instance (a
            # per-change port, DB, output dir) instead of guessing.
            #
            # A BOOTSTRAP change (one that writes or edits scripts/proof.sh or
            # a probe) runs no adapter at all. The copy land holds is the copy
            # this change replaces, so running it proves the OLD adapter passes
            # against the new code. A green run would auto-land a change to
            # the proof adapter itself. The documented contract gives this case
            # no automatic route: the human runs the branch's own adapter from
            # the worktree and attests with its output.
            local proof_root="$main_root" proof_wt=""
            [ -d "$wt" ] && { proof_root="$wt"; proof_wt="$wt"; }
            # The trailer's own description only ever appears in a refusal, so
            # each refusal reads it for itself and a green land pays for it.
            if [ -f "$main_root/scripts/proof.sh" ] && [ -z "$bootstrap" ]; then
                if ! ( cd "$proof_root" \
                       && HONE_CHANGE="$change" HONE_BRANCH="$branch" \
                          HONE_WORKTREE="$proof_wt" HONE_MAIN_ROOT="$main_root" \
                          bash "$main_root/scripts/proof.sh" "$change" ); then
                    check=$(land_proof_trailer "$main_root" "$base" "$branch")
                    msg_wt_land_proof_adapter_failed "$branch" "$check" "$attest_cmd" "$bootstrap" >&2
                    return 7
                fi
            elif [ -f "$signoff" ]; then
                # A sign-off exists but does not name this tip. That is the
                # precise diagnosis, and it comes BEFORE the marker's
                # no-adapter refusal. The human already knows the attest route
                # and only has to run it again for the new tip. The marker
                # message would instead hide that route and offer removing
                # project policy.
                check=$(land_proof_trailer "$main_root" "$base" "$branch")
                msg_wt_land_proof_signoff_stale "$change" "$branch" "$tip" "$check" "$attest_cmd" "$bootstrap" >&2
                return 7
            elif [ -n "$proof_always" ] && [ ! -f "$main_root/scripts/proof.sh" ]; then
                # The marker asked for an adapter run on every change, and
                # there is no adapter. Refusing beats quietly proving nothing.
                # A bootstrap change skipped an adapter that DOES exist, so it
                # never reaches this branch and never reads that it is missing.
                msg_wt_land_proof_always_no_adapter "$HONE_PLUGIN_ROOT/templates/proof/" >&2
                return 7
            else
                check=$(land_proof_trailer "$main_root" "$base" "$branch")
                if [ -n "$bootstrap" ] && [ -z "$check" ]; then
                    # The change declared nothing, and the adapter edit alone
                    # opened the gate. Saying "this branch declares
                    # real-environment proof" would name a trailer that is not
                    # there, so this refusal names the file change instead.
                    msg_wt_land_proof_adapter_change "$branch" "$attest_cmd" "$bootstrap" >&2
                else
                    msg_wt_land_proof_missing "$branch" "$check" "$attest_cmd" "$bootstrap" >&2
                fi
                return 7
            fi
        fi
    fi

    # Read the landed lockfiles BEFORE the merge and cleanup below: the
    # setup-tree run keys on them, and the cleanup deletes the branch the
    # diff needs. The merge base stays put across the shared-mode retries
    # below: the branch tip never moves, so neither do the gates above.
    local lockfiles
    lockfiles=$(land_lockfiles "$main_root" "$base" "$branch")
    local -a merge_args=(merge --no-ff "$branch" -m "Merge branch '$branch'")
    # The grant's text becomes a second commit paragraph. The authorization is
    # then in git history. The first line stays "Merge branch 'hone/<change>'" so
    # the nag's landed-Plan grep still matches.
    [ -n "$grant_note" ] && merge_args+=(-m "Authorized (irreversible change):"$'\n'"$grant_note")
    # The sign-off that discharged the proof gate gets the same treatment.
    [ -n "$signoff_note" ] && merge_args+=(-m "Proven (real-environment):"$'\n'"$signoff_note")
    local remote="" primary="" attempt=1 retries="${HONE_LAND_RETRIES:-3}"
    # A count that is not a whole number never compares true, and the retry
    # loop below would never end.
    case "$retries" in
        ''|*[!0-9]*) msg_wt_land_bad_retries "$retries" >&2; return 2 ;;
    esac
    remote=$(shared_remote_checked "$main_root") || { [ $? -eq 2 ] && return 2; }
    [ -n "$remote" ] && primary=$(git -C "$main_root" symbolic-ref -q --short HEAD)
    local primary_name
    primary_name=$(git -C "$main_root" symbolic-ref -q --short HEAD)
    # The merge is built and verified in the change's WORKTREE, never in the
    # primary tree. The primary tree is shared: other sessions commit Plans
    # onto it and leave draft files in it while a land runs. A post-merge
    # suite there read those drafts and rolled back correct changes, and its
    # rollback (a hard reset to the pre-merge commit) dropped a Plan commit
    # that another session made during the suite. So land checks out the
    # primary branch's tip in the worktree, merges the branch there, and runs
    # the suite and the adapters on that merge commit. Only a green merge
    # reaches the primary branch, by a fast-forward. A fast-forward moves
    # nothing but the branch and the files the merge changed, and it refuses
    # rather than overwrite a person's uncommitted edit. A red merge never
    # touched the primary tree, so nothing needs a rollback there.
    local pre land_log setup_tree_ran="" adapter zero_tiers merge_sha="" tree_lockfiles
    # The worktree is the verify tree. It already holds the branch and its
    # installed dependencies. A land whose worktree is gone (a person removed
    # it) cuts it again from the branch, the way add does.
    if [ ! -d "$wt" ]; then
        local add_log
        add_log="$(cd "$common_dir" 2>/dev/null && pwd || printf '%s' "$common_dir")/hone-land.log"
        if ! git -C "$main_root" worktree add -q "$wt" "$branch" >"$add_log" 2>&1; then
            msg_wt_land_rebuild_failed "$wt" "$add_log" "$(tail -n 20 "$add_log" 2>/dev/null)" >&2
            return 2
        fi
        if [ -f "$wt/scripts/setup-tree.sh" ]; then
            local setup_out
            if ! setup_out=$( (cd "$wt" && bash scripts/setup-tree.sh) 2>&1 ); then
                msg_wt_add_setup_tree_failed "$wt" "$(printf '%s\n' "$setup_out" | tail -n 20)" >&2
                return 2
            fi
        fi
    fi
    # A tracked edit that nobody committed is not part of the branch, and the
    # checkout below would carry it into the merge. Refuse before anything
    # moves.
    if [ -n "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        msg_wt_land_worktree_dirty "$wt" >&2
        return 2
    fi
    # A file that git does not track and does not ignore is in the worktree,
    # so the suite there sees it. The merge does not carry it, so the primary
    # tree would get a change that passed only with that file beside it.
    # Refuse, so the suite on the merge sees exactly what lands.
    local untracked
    untracked=$(git -C "$wt" ls-files --others --exclude-standard --directory 2>/dev/null)
    if [ -n "$untracked" ]; then
        msg_wt_land_worktree_untracked "$wt" "$(sed 's/^/- /' <<<"$untracked")" >&2
        return 2
    fi
    # Shared mode: the primary branch belongs to the team, so the merge goes
    # on top of the team's latest and the result is pushed. Git rejects the
    # push when the remote moved while the suite ran, and a rejected push
    # means the combination on the remote was never tested. Solo mode has
    # the same race inside one clone: another session commits a Plan onto
    # the primary branch during the suite, and the fast-forward refuses. In
    # both cases land merges again on the new tip and verifies again, up to
    # HONE_LAND_RETRIES times. Nothing untested ever reaches the branch.
    # From the checkout until the fast-forward, the worktree sits detached on
    # a merge. A land killed there (a signal, a timeout) left it detached, and
    # the next commit in it landed on no branch. So a trap puts it back on
    # its branch on any exit, and the fast-forward disarms it.
    trap land_on_exit EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    while :; do
    # The fast-forward below moves whatever branch the primary tree has
    # checked out. A person who switched it during a suite would get the
    # merge on another branch. So each attempt, and the fast-forward, check
    # that the primary tree is still on the branch land started on.
    if ! land_on_primary "$main_root" "$primary_name"; then
        land_restore_tree "$wt" "$branch" "$setup_tree_ran"
        msg_wt_land_primary_switched "$primary_name" >&2
        return 2
    fi
    if [ -n "$remote" ]; then
        shared_sync_primary "$main_root" "$remote" "$primary" || { land_restore_tree "$wt" "$branch" "$setup_tree_ran"; return 2; }
    fi
    pre=$(git -C "$main_root" rev-parse HEAD)
    # Keep the output of the merge and of the run on it. On red it is the
    # only record of what broke. One file per primary tree, and each land
    # overwrites it.
    land_log="$(cd "$common_dir" 2>/dev/null && pwd || printf '%s' "$common_dir")/hone-land.log"
    : >"$land_log"
    LAND_PENDING_WT="$wt" LAND_PENDING_BRANCH="$branch" LAND_PENDING_REINSTALL="$setup_tree_ran"
    if ! git -C "$wt" checkout -q --detach "$pre" >>"$land_log" 2>&1; then
        land_restore_tree "$wt" "$branch" "$setup_tree_ran"
        msg_wt_land_merge_failed "$branch" "$land_log" "$(tail -n 20 "$land_log" 2>/dev/null)" >&2
        return 2
    fi
    if ! git -C "$wt" "${merge_args[@]}" >>"$land_log" 2>&1; then
        # A failed merge has three causes, and each needs another action. Read
        # the state before the abort erases it. Every case puts the worktree
        # back on its branch and keeps the branch.
        local unmerged merging=""
        unmerged=$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null)
        git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && merging=yes
        git -C "$wt" merge --abort >/dev/null 2>&1
        land_restore_tree "$wt" "$branch" "$setup_tree_ran"
        # Unmerged paths: a real conflict, so the independence check missed
        # an overlap. Its own exit code (9) means "fold in serially".
        if [ -n "$unmerged" ]; then
            msg_wt_land_conflict "$branch" "$(sed 's/^/- /' <<<"$unmerged")" >&2
            return 9
        fi
        # A clean merge that git did not commit: a git hook (pre-merge-commit,
        # commit-msg) refused the merge commit. Like a red adapter, a check
        # failed on the merged tree, so it shares exit 6. The fix is what the
        # hook reports. Folding in serially would change nothing.
        if [ -n "$merging" ]; then
            msg_wt_land_hook_refused "$branch" "$land_log" "$(tail -n 20 "$land_log" 2>/dev/null)" >&2
            return 6
        fi
        # git refused before it merged anything, for example because a lock
        # file was in the way. That is repo state, so exit 2.
        msg_wt_land_merge_failed "$branch" "$land_log" "$(tail -n 20 "$land_log" 2>/dev/null)" >&2
        return 2
    fi
    merge_sha=$(git -C "$wt" rev-parse HEAD)
    # The worktree's installed dependencies match the branch's lockfiles. A
    # lockfile that the primary branch changed since the cut leaves them
    # behind the merge, and a suite over a stale install judges the install,
    # not the change. The optional setup-tree adapter closes the gap. A red
    # adapter fails the land exactly like a red suite. The flag stays set
    # across attempts: once any attempt installed a merge's dependencies,
    # every restore must install the branch's again.
    tree_lockfiles=$(land_lockfiles "$main_root" "$branch" "$merge_sha")
    if [ -n "$tree_lockfiles" ] && [ -f "$wt/scripts/setup-tree.sh" ]; then
        setup_tree_ran=yes
        LAND_PENDING_REINSTALL=yes
        if ! ( cd "$wt" && bash scripts/setup-tree.sh ) >>"$land_log" 2>&1; then
            land_restore_tree "$wt" "$branch" "$setup_tree_ran"
            msg_wt_land_setup_tree_red "$branch" "$land_log" "$(tail -n 20 "$land_log" 2>/dev/null)" >&2
            return 6
        fi
    fi
    if ! ( cd "$wt" && bash scripts/run-tests.sh --all ) >>"$land_log" 2>&1; then
        # Red means the merge regresses the trunk. The primary branch never
        # moved. The worktree goes back to its branch for investigation.
        land_restore_tree "$wt" "$branch" "$setup_tree_ran"
        msg_wt_land_suite_red "$branch" "$land_log" "$(tail -n 20 "$land_log" 2>/dev/null)" >&2
        return 6
    fi
    # The gate holds every worktree to tests, type-check, and lint. The merge
    # result is a third tree: two changes that each append to one file can be
    # lint-green alone and lint-red merged. So land re-runs the same optional
    # adapters the gate runs, into the same log.
    for adapter in typecheck lint; do
        [ -f "$wt/scripts/$adapter.sh" ] || continue
        if ! ( cd "$wt" && bash "scripts/$adapter.sh" ) >>"$land_log" 2>&1; then
            land_restore_tree "$wt" "$branch" "$setup_tree_ran"
            msg_wt_land_adapter_red "$adapter" "$branch" "$land_log" "$(tail -n 20 "$land_log" 2>/dev/null)" >&2
            return 6
        fi
    done
    # Green, but green over nothing is not green. A tier whose selection stopped
    # matching (a moved directory, a renamed suffix) exits 0 on zero tests. The
    # land log is the one place that shows it. Advisory: the merge stands,
    # and the human decides.
    zero_tiers=$(land_zero_tiers "$land_log")
    [ -n "$zero_tiers" ] && msg_wt_land_tier_empty "$zero_tiers" >&2
    # Publish the tested merge: fast-forward the primary branch onto it. The
    # fast-forward refuses when the branch moved during the suite, because
    # the merge no longer extends it. Then the combination on the branch was
    # never tested, so land goes around again.
    if ! land_on_primary "$main_root" "$primary_name"; then
        land_restore_tree "$wt" "$branch" "$setup_tree_ran"
        msg_wt_land_primary_switched "$primary_name" >&2
        return 2
    fi
    if git -C "$main_root" merge -q --ff-only "$merge_sha" >>"$land_log" 2>&1; then
        LAND_PENDING_WT=""
    else
        if [ "$(git -C "$main_root" rev-parse HEAD)" != "$pre" ]; then
            if [ "$attempt" -ge "$retries" ]; then
                land_restore_tree "$wt" "$branch" "$setup_tree_ran"
                msg_wt_land_primary_moved "$primary_name" "$retries" >&2
                return 5
            fi
            attempt=$((attempt+1))
            msg_wt_land_retry_moved "$primary_name" "$attempt" >&2
            continue
        fi
        # The branch did not move, so a file in the primary tree refused the
        # fast-forward: an uncommitted edit or an untracked file that the
        # merge would overwrite. land never overwrites a person's file.
        land_restore_tree "$wt" "$branch" "$setup_tree_ran"
        msg_wt_land_ff_refused "$branch" "$land_log" "$(tail -n 20 "$land_log" 2>/dev/null)" >&2
        return 2
    fi
    # Shared mode: publish the tested merge. A rejection means the remote
    # moved under the suite. Undo the local fast-forward and go around again.
    # The undo is a keep-reset, and only while the primary branch still sits
    # on the merge. A hard reset would drop a commit that another session
    # made on top, or an uncommitted edit in the primary tree.
    if [ -n "$remote" ]; then
        local push_rc=0
        shared_push_once "$main_root" "$remote" "$primary" || push_rc=$?
        if [ "$push_rc" -ne 0 ]; then
            if [ "$(git -C "$main_root" rev-parse HEAD)" = "$merge_sha" ]; then
                git -C "$main_root" reset -q --keep "$pre" >/dev/null 2>&1
            fi
            # A refused push (a protected branch, a lost remote) has no retry
            # that helps. The message already said so.
            if [ "$push_rc" -ne 3 ]; then
                land_restore_tree "$wt" "$branch" "$setup_tree_ran"
                return 2
            fi
            if [ "$attempt" -ge "$retries" ]; then
                land_restore_tree "$wt" "$branch" "$setup_tree_ran"
                msg_wt_land_push_rejected "$remote" "$primary" "$retries" >&2
                return 5
            fi
            attempt=$((attempt+1))
            msg_wt_land_retry "$remote" "$primary" "$attempt" >&2
            LAND_PENDING_WT="$wt"
            continue
        fi
    fi
    break
    done
    trap - EXIT HUP INT TERM
    # The merge is on the primary branch now. The merge commit is the one the
    # suite judged, so the receipt names it, not whatever HEAD is by now.
    merge_sha=$(git -C "$main_root" rev-parse --short "$merge_sha")
    # The fast-forward moved the primary tree's lockfiles past its installed
    # dependencies. Reinstall there when the project ships setup-tree. The
    # merge already stands, so a red install is a warning, not a failure.
    local primary_setup=""
    if [ -n "$lockfiles" ] && [ -f "$main_root/scripts/setup-tree.sh" ]; then
        if ( cd "$main_root" && bash scripts/setup-tree.sh ) >>"$land_log" 2>&1; then
            primary_setup=ran
        else
            primary_setup=failed
        fi
    fi
    # Retire the worktree and its branch (cmd_remove runs from the primary
    # tree, so it never refuses "the tree you are in"). The worktree sits on
    # the merge commit now, so land deletes the branch itself. In shared mode
    # remove also releases the claim on the remote: the change is on the
    # remote primary now. A worktree that will not go (the suite left a file
    # in it) is a leftover to clean by hand, not a failed land. remove's own
    # refusal asks to commit the changes, which is wrong after a land, so
    # land says it instead and names the files.
    local remove_rc=0 remove_err leftovers=""
    remove_err=$(cmd_remove "$wt" 2>&1 >/dev/null) || remove_rc=$?
    if [ "$remove_rc" -eq 0 ]; then
        [ -n "$remove_err" ] && printf '%s\n' "$remove_err" >&2
    else
        leftovers=$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null | head -n 20)
    fi
    git -C "$main_root" branch -d "$branch" >/dev/null 2>&1 || msg_wt_remove_branch_kept "$branch" >&2
    # The claim goes with the landed change, whether or not the worktree went.
    # A kept worktree would otherwise hold the change name for the team.
    if [ -n "$remote" ]; then
        shared_release "$main_root" "$remote" "$change" \
            || msg_wt_land_claim_delete_failed "$change" "$remote" >&2
    fi

    # Land hygiene 3: the change's records go with its worktree and branch.
    # Every record that opened a gate has its text in the merge commit body
    # above, so deleting the files loses no audit trail. A record that opened
    # nothing (a stale sign-off beside a green adapter run) vouched for
    # nothing that landed, so it goes the same way. See land_consume_record
    # on why a leftover grant is unsafe.
    local consumed="" rec
    for rec in ".hone-grant" ".hone-proof"; do
        rec=$(land_consume_record "$main_root/$rec" "$change")
        [ -n "$rec" ] && consumed="$consumed${consumed:+ }$rec"
    done

    # Say what happened. A silent exit 0 made the caller re-derive the outcome
    # from `git log`, so the receipt names the merge commit, the green suite,
    # and the cleanup. It goes to stdout, because it is the success path.
    local kept=""
    [ "$remove_rc" -eq 0 ] || kept="$wt"
    msg_wt_land_receipt "$merge_sha" "$branch" "$consumed" "$kept"
    [ -n "$kept" ] && msg_wt_land_worktree_kept "$kept" "bash $HONE_WSH remove $change" "$leftovers"
    [ -n "$remote" ] && msg_wt_land_pushed "$remote" "$primary"
    if [ -n "$lockfiles" ]; then
        case "$primary_setup" in
            ran)    msg_wt_land_setup_tree_receipt "$lockfiles" ;;
            failed) msg_wt_land_setup_tree_primary_failed "$lockfiles" "$land_log" ;;
            *)      msg_wt_land_lockfile "$lockfiles" ;;
        esac
    fi
    return 0
}

# Put the change's worktree back on its branch after a land that did not
# publish. The checkout discards what the merge and the suite left in tracked
# files. The branch holds every commit, so nothing of the change is lost. A
# setup-tree run for the merge ($3 non-empty) left the merge's dependencies
# installed, so the adapter runs again for the branch.
land_restore_tree() {
    local wt="$1" branch="$2" reinstall="${3:-}"
    LAND_PENDING_WT=""
    git -C "$wt" checkout -q -f "$branch" >/dev/null 2>&1
    if [ -n "$reinstall" ] && [ -f "$wt/scripts/setup-tree.sh" ]; then
        ( cd "$wt" && bash scripts/setup-tree.sh ) >/dev/null 2>&1
    fi
    return 0
}

# Exit 0 when the primary tree at $1 has branch $2 checked out.
land_on_primary() {
    [ "$(git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null)" = "$2" ]
}

# The EXIT trap of a land. It restores the worktree only while a merge is
# pending in it. An explicit restore, or the fast-forward, clears the state.
LAND_PENDING_WT="" LAND_PENDING_BRANCH="" LAND_PENDING_REINSTALL=""
land_on_exit() {
    [ -n "$LAND_PENDING_WT" ] || return 0
    land_restore_tree "$LAND_PENDING_WT" "$LAND_PENDING_BRANCH" "$LAND_PENDING_REINSTALL"
}

# Resolve the main tree's root (the common git dir's parent), the anchor every
# subcommand that must not depend on cwd uses.
main_root_of() {
    git -C "$(git rev-parse --git-common-dir 2>/dev/null)/.." rev-parse --show-toplevel 2>/dev/null
}

# ---- shared mode -------------------------------------------------------
# A committed .hone-shared marker in the primary tree turns shared mode on.
# Its first non-comment line names the remote, and a blank file means
# origin. In shared mode the primary branch belongs to the team, on that
# remote: add claims a change by pushing a claim ref, land pushes the
# merge, and landed/sync read the remote. Without the marker nothing here
# runs, so a solo repo with a backup remote never starts pushing on an
# upgrade.
shared_remote() {
    local f="$1/.hone-shared" remote
    [ -f "$f" ] || return 0
    remote=$(grep -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    printf '%s\n' "${remote:-origin}"
}
remote_exists() {
    git -C "$1" remote get-url "$2" >/dev/null 2>&1
}
# Resolve the shared remote for a command that needs one, or say why not.
# Prints the remote name. Exit 0 with a name · 1 not shared (silent) · 2 the
# marker names a remote this repo lacks (message printed).
shared_remote_checked() {
    local main_root="$1" remote
    remote=$(shared_remote "$main_root")
    [ -n "$remote" ] || return 1
    if ! remote_exists "$main_root" "$remote"; then
        msg_wt_sync_no_remote "$remote" >&2; return 2
    fi
    printf '%s\n' "$remote"
}
# Bring the primary tree level with <remote>/<primary>. Fetch into the
# remote-tracking ref by explicit refspec (FETCH_HEAD is per-worktree and
# shared by every concurrent fetch, so it is not a stable handle). Then:
# equal or local-ahead needs nothing (a later push carries the local
# commits), remote-ahead fast-forwards, and diverged rebases the local-only
# commits on top. Those are Plan commits, usually, and --rebase-merges keeps
# an earlier merge commit intact instead of flattening it. The tree must be
# clean for either move. Exit 0 level · 2 fetch failed, dirty, or a rebase
# conflict (aborted, message printed).
shared_sync_primary() {
    local main_root="$1" remote="$2" primary="$3" out upstream
    upstream="refs/remotes/$remote/$primary"
    if ! out=$(git -C "$main_root" fetch -q "$remote" "+refs/heads/$primary:$upstream" 2>&1); then
        msg_wt_sync_fetch_failed "$remote" "$(printf '%s\n' "$out" | tail -n 5)" >&2
        return 2
    fi
    git -C "$main_root" merge-base --is-ancestor "$upstream" HEAD 2>/dev/null && return 0
    if [ -n "$(git -C "$main_root" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        msg_wt_sync_dirty "$primary" >&2
        return 2
    fi
    if git -C "$main_root" merge-base --is-ancestor HEAD "$upstream" 2>/dev/null; then
        git -C "$main_root" merge -q --ff-only "$upstream" >/dev/null 2>&1 && return 0
    fi
    if ! out=$(git -C "$main_root" rebase -q --rebase-merges "$upstream" 2>&1); then
        git -C "$main_root" rebase --abort >/dev/null 2>&1
        msg_wt_sync_diverged "$remote" "$primary" "$(printf '%s\n' "$out" | tail -n 10)" >&2
        return 2
    fi
}
# Push the primary branch once, and say why not. Git rejects the push when
# the remote moved since the fetch, and a host rejects it when the branch is
# protected. The two need different answers, so on a rejection this fetches
# again: a moved remote means "sync and retry", an unmoved one means the
# host refused, and no retry will help. Exit 0 pushed (or nothing to push)
# · 3 the remote moved · 2 refused (message printed) or the fetch failed.
shared_push_once() {
    local main_root="$1" remote="$2" primary="$3" upstream before after out
    upstream="refs/remotes/$remote/$primary"
    before=$(git -C "$main_root" rev-parse -q --verify "$upstream" 2>/dev/null)
    out=$(git -C "$main_root" push -q "$remote" "refs/heads/$primary:refs/heads/$primary" 2>&1) && return 0
    if ! git -C "$main_root" fetch -q "$remote" "+refs/heads/$primary:$upstream" >/dev/null 2>&1; then
        msg_wt_sync_fetch_failed "$remote" "$(printf '%s\n' "$out" | tail -n 5)" >&2
        return 2
    fi
    after=$(git -C "$main_root" rev-parse -q --verify "$upstream" 2>/dev/null)
    [ "$before" != "$after" ] && return 3
    msg_wt_push_refused "$remote" "$primary" "$(printf '%s\n' "$out" | tail -n 5)" >&2
    return 2
}
# Push the primary branch, syncing and retrying while the remote keeps
# moving, up to three times. Exit 0 pushed (or nothing to push) · 2 sync
# failed or refused · 5 the remote moved every time.
shared_push_primary() {
    local main_root="$1" remote="$2" primary="$3" attempt rc
    for attempt in 1 2 3; do
        # Level first: a clone that is merely behind must never read as
        # "refused", and after a sync a rejection means moved or refused.
        shared_sync_primary "$main_root" "$remote" "$primary" || return 2
        rc=0; shared_push_once "$main_root" "$remote" "$primary" || rc=$?
        [ "$rc" -eq 3 ] || return "$rc"
    done
    msg_wt_land_push_rejected "$remote" "$primary" 3 >&2
    return 5
}
# The claim. A branch ref alone cannot be one: two developers on the same
# primary HEAD cut identical branch refs, and git answers the second push
# with "up to date" before it checks any lease. So the claim is its own ref,
# refs/hone/claim/<change>, pointing at a detached root commit whose message
# says who claimed, where, and when. That commit is unique per claimant, so
# the second push is a non-fast-forward, and the empty lease says the ref
# must not exist yet. Exactly one developer wins. The commit is on no
# branch, so it never reaches history. Exit 0 claimed · 4 someone else
# holds it · 2 push failed (message printed).
shared_claim() {
    local main_root="$1" remote="$2" change="$3" ref sha out
    ref="refs/hone/claim/$change"
    sha=$(git -C "$main_root" commit-tree "$(git -C "$main_root" hash-object -t tree /dev/null)" \
            -m "hone claim: $change by $(git config user.name 2>/dev/null || echo unknown) <$(git config user.email 2>/dev/null || echo unknown)> on $(hostname 2>/dev/null || echo unknown) at $(date -Iseconds)") \
        || { msg_wt_add_push_failed "$ref" "$remote" "" >&2; return 2; }
    if out=$(git -C "$main_root" push -q "$remote" --force-with-lease="$ref:" "$sha:$ref" 2>&1); then
        git -C "$main_root" update-ref "$ref" "$sha"
        return 0
    fi
    if git -C "$main_root" ls-remote --exit-code "$remote" "$ref" >/dev/null 2>&1; then
        return 4
    fi
    msg_wt_add_push_failed "$ref" "$remote" "$(printf '%s\n' "$out" | tail -n 5)" >&2
    return 2
}
shared_release() {
    local main_root="$1" remote="$2" change="$3" ref
    ref="refs/hone/claim/$change"
    git -C "$main_root" update-ref -d "$ref" >/dev/null 2>&1
    git -C "$main_root" ls-remote --exit-code "$remote" "$ref" >/dev/null 2>&1 || return 0
    git -C "$main_root" push -q "$remote" --delete "$ref" >/dev/null 2>&1
}

# Print non-empty if $1 is one of the placeholder descriptions hone itself
# prints, quoted or bare, in any case. The list lives in messages.sh
# (hone_msg_attest_placeholders), beside the usage lines and the remedy command
# that carry those literals, so the two can never drift apart.
attest_is_placeholder() {
    local what candidate
    what=$(printf '%s' "$1" | tr 'A-Z' 'a-z' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
              -e 's/^["'"'"']//' -e 's/["'"'"']$//' \
              -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    while IFS= read -r candidate; do
        [ "$what" = "$candidate" ] && { echo yes; return 0; }
    done < <(hone_msg_attest_placeholders)
}

# Print non-empty if $1 still reads as the "who/why" placeholder from the
# usage lines (hone_msg_grant_why), quoted or bare, in any case. A half-edited
# form counts too: any whitespace-free text whose why half is still the bare
# word "why". An audit found a grant reading "rehse/why" on a repo's largest
# irreversible change. The who half was filled in, the why half was not, and
# the file authorized nothing a reader could check.
grant_is_placeholder() {
    local why
    why=$(printf '%s' "$1" | tr 'A-Z' 'a-z' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
              -e 's/^["'"'"']//' -e 's/["'"'"']$//' \
              -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ "$why" = "$(hone_msg_grant_why)" ] && { echo yes; return 0; }
    case "$why" in
        *[[:space:]]*) ;;
        why|*/why) echo yes; return 0 ;;
    esac
}

# "name <email> | timestamp" for grant/attest stamps, with "agent " in front
# when the agent ran the helper rather than a person.
#
# Both may run it, and the record has to say which. The git identity is the
# repository owner's either way, so an unmarked stamp would read as a person's
# authorization for every grant the loop records. CLAUDECODE is set in the
# agent's shell and unset in a terminal the person drives, which is the one
# signal available here. It is a label, not a lock: the agent could unset it,
# and this is a record for a reader, not a defence against one.
signer_stamp() {
    printf '%s%s <%s> | %s' \
        "${CLAUDECODE:+agent, on behalf of }" \
        "$(git config user.name 2>/dev/null || echo unknown)" \
        "$(git config user.email 2>/dev/null || echo unknown)" \
        "$(date -Iseconds)"
}

# The mechanical landed predicate (header: `worktree.sh landed`). Like
# review_scope it prints a bare word, because the caller reads the word and
# the exit code, never its own judgment. The merge-commit grep is the positive
# signal: without it, a change nobody ever started would also show no branch,
# no worktree, and no Plan. -F pins the quotes, so `hone/a` never matches a
# nested `hone/a/b`.
cmd_landed() {
    local change="${1:-}"
    [ -n "$change" ] || { msg_wt_needs_change landed >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }
    local main_root branch
    main_root=$(main_root_of)
    branch="hone/$change"
    # Shared mode: "landed" means landed for the TEAM, so the questions go to
    # the remote primary branch, not the local one. A fetch that fails, or a
    # remote branch that still exists, both read as pending: the orchestrator
    # keeps polling, and a wrong "landed" would start a dependent Plan early.
    local ref=HEAD remote="" primary
    remote=$(shared_remote_checked "$main_root") || { [ $? -eq 2 ] && return 2; }
    if [ -n "$remote" ]; then
        primary=$(git -C "$main_root" symbolic-ref -q --short HEAD) || {
            msg_wt_land_detached >&2; return 2; }
        ref="refs/remotes/$remote/$primary"
        git -C "$main_root" fetch -q "$remote" "+refs/heads/$primary:$ref" >/dev/null 2>&1 \
            || { printf 'pending\n'; return 1; }
        if git -C "$main_root" ls-remote --exit-code "$remote" "refs/hone/claim/$change" >/dev/null 2>&1; then
            printf 'pending\n'; return 1
        fi
    fi
    # -n 1 and a capture, never `| grep -q .`. The grep quit on the first hash,
    # git took SIGPIPE writing the next one, and pipefail turned that 141 into
    # "no merge found". A change that an older land rolled back and landed
    # again carries several matching merge subjects, so exactly the landed
    # changes read as pending, and a ready --all chain stalled on its one
    # completion signal.
    local merge
    merge=$(git -C "$main_root" log -F --grep="Merge branch '$branch'" --format=%H -n 1 "$ref" 2>/dev/null)
    if git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch" \
        || [ -e "$main_root/.worktrees/$change" ] \
        || git -C "$main_root" cat-file -e "$ref:.plans/$change.md" 2>/dev/null \
        || [ -z "$merge" ]; then
        printf 'pending\n'
        return 1
    fi
    printf 'landed\n'
}

# Level the primary tree with the team's primary branch, both ways: fetch and
# fast-forward or rebase, then push local-only commits (a fresh Plan). The
# plan skill runs it after committing a Plan, so the Plan reaches the team's
# queue, and a human runs it to catch up. Under the land lock, like every
# move of the primary HEAD.
cmd_sync() {
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }
    command -v flock >/dev/null 2>&1 || { msg_wt_no_flock sync >&2; return 2; }
    local main_root remote primary
    main_root=$(main_root_of)
    remote=$(shared_remote_checked "$main_root") || {
        [ $? -eq 2 ] && return 2
        msg_wt_sync_not_shared >&2; return 2; }
    primary=$(git -C "$main_root" symbolic-ref -q --short HEAD) || {
        msg_wt_land_detached >&2; return 2; }
    exec 9>"$(git -C "$main_root" rev-parse --git-common-dir)/hone-land.lock" || return 2
    flock -w "${HONE_LAND_LOCK_TIMEOUT:-600}" 9 || {
        msg_wt_lock_timeout "${HONE_LAND_LOCK_TIMEOUT:-600}" >&2; return 5; }
    shared_push_primary "$main_root" "$remote" "$primary" || return $?
    msg_wt_sync_receipt "$remote" "$primary"
}

# Release a claim by hand: an abandoned change whose worktree is already
# gone, or a claim a crashed run left behind. Shared mode only.
cmd_release() {
    local change="${1:-}"
    [ -n "$change" ] || { msg_wt_needs_change release >&2; return 2; }
    git rev-parse --git-dir >/dev/null 2>&1 || { msg_wt_not_a_repo >&2; return 2; }
    local main_root remote
    main_root=$(main_root_of)
    remote=$(shared_remote_checked "$main_root") || {
        [ $? -eq 2 ] && return 2
        msg_wt_release_not_shared >&2; return 2; }
    shared_release "$main_root" "$remote" "$change" || {
        msg_wt_land_claim_delete_failed "$change" "$remote" >&2; return 2; }
    msg_wt_release_receipt "$change" "$remote"
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
    for a in run-tests typecheck lint proof setup-tree; do
        if [ -f "scripts/$a.sh" ]; then line+=" $a=yes"; else line+=" $a=no"; fi
    done
    msg_status_adapters "$line"

    local pf n
    for pf in .hone-durable-paths .hone-irreversible-paths .hone-consequential-paths \
              .hone-review-always; do
        [ -f "$pf" ] || continue
        n=$(grep -cvE '^[[:space:]]*(#|$)' "$pf" 2>/dev/null || true)
        if git ls-files --error-unmatch "$pf" >/dev/null 2>&1; then
            msg_status_policy "$pf" "${n:-0}"
        else
            msg_status_policy_uncommitted "$pf" "${n:-0}"
        fi
        [ "$pf" = ".hone-consequential-paths" ] && msg_status_policy_legacy
    done

    # The proof-always marker is project policy like the path lists, so an
    # uncommitted one gets the same warning: it gates this developer's lands
    # and nobody else's.
    if [ -f ".hone-proof-always" ]; then
        if git ls-files --error-unmatch .hone-proof-always >/dev/null 2>&1; then
            msg_status_proof_always
        else
            msg_status_proof_always_uncommitted
        fi
    fi

    # Shared mode is project policy like the markers above, so an uncommitted
    # marker gets the same warning.
    local remote=""
    if [ -f ".hone-shared" ]; then
        remote=$(shared_remote "$main_root")
        if ! remote_exists "$main_root" "$remote"; then
            msg_status_shared_no_remote "$remote"; remote=""
        elif git ls-files --error-unmatch .hone-shared >/dev/null 2>&1; then
            msg_status_shared "$remote"
        else
            msg_status_shared_uncommitted "$remote"
        fi
    fi

    local plan change pending=0
    while IFS= read -r plan; do
        [ -f "$(dirname "$plan").md" ] && continue   # a Plan's reference, not a Plan
        change=${plan#.plans/}; change=${change%.md}
        [ -d ".worktrees/$change" ] && continue      # mid-run, and its worktree appears below
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
    # Other developers' claims: refs/hone/claim/* on the remote with no
    # worktree here, each with its record (who, where, when). A remote that
    # does not answer lists nothing, and status stays 0.
    if [ -n "$remote" ]; then
        local cref
        # Into refs/hone/remote-claim/, never refs/hone/claim/: that prefix
        # holds this clone's OWN claims, and the nag reads it as such.
        git fetch -q --prune "$remote" '+refs/hone/claim/*:refs/hone/remote-claim/*' >/dev/null 2>&1
        while IFS= read -r cref; do
            [ -n "$cref" ] || continue
            [ -d ".worktrees/${cref#refs/hone/remote-claim/}" ] && continue
            msg_status_remote_claim "$(git log -1 --format=%s "$cref" 2>/dev/null)" "$remote"
        done < <(git for-each-ref --format='%(refname)' 'refs/hone/remote-claim/' 2>/dev/null)
    fi

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
    # A grant IS its text: land copies it into the merge commit body, and a
    # later reader checks the authorization there. Whitespace records nothing,
    # and the unedited placeholder records less than nothing, because it reads
    # as an authorization while naming none. Same rule as attest.
    if ! printf '%s' "$why" | grep '[^[:space:]]' >/dev/null; then
        msg_wt_grant_empty >&2; return 2
    fi
    if [ -n "$(grant_is_placeholder "$why")" ]; then
        msg_wt_grant_placeholder "$why" >&2; return 2
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
    # A sign-off IS its text: land reads the commit id, a human reads the rest.
    # Whitespace records nothing, and the unedited placeholder records less than
    # nothing, because it reads as evidence while carrying none.
    if ! printf '%s' "$what" | grep '[^[:space:]]' >/dev/null; then
        msg_wt_attest_empty >&2; return 2
    fi
    if [ -n "$(attest_is_placeholder "$what")" ]; then
        msg_wt_attest_placeholder "$what" >&2; return 2
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

    # Accept the three spellings a caller uses: an absolute path, a path
    # relative to the caller's directory, and a bare change name. The run
    # skill itself passed `.worktrees/<change>`, and the absolute-only test
    # answered that hone had not created the worktree.
    case "$wt" in
        /*) : ;;
        *)
            if [ -d "${WT_CALLER_PWD:-$PWD}/$wt" ]; then
                wt=$(cd "${WT_CALLER_PWD:-$PWD}/$wt" && pwd -P)
            elif [ -d "$main_root/.worktrees/$wt" ]; then
                wt="$main_root/.worktrees/$wt"
            fi
            ;;
    esac
    wt="${wt%/}"
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
    # Shared mode: the worktree was the change's local half, and the claim on
    # the remote is the other half. Release it, so an abandoned change does
    # not block its name for the team. A land calls remove before its own
    # release, and releasing twice is harmless.
    local remote
    remote=$(shared_remote_checked "$main_root") || { [ $? -eq 2 ] && return 2; }
    [ -n "$remote" ] && shared_release "$main_root" "$remote" "${wt#"$main_root"/.worktrees/}"

    # Land hygiene 1: a landed change's branch goes with its worktree. `-d`
    # (not -D), so an unmerged branch (abandoned or unlanded work) survives as
    # evidence.
    case "$branch" in
        hone/*)
            if ! git branch -d "$branch" >/dev/null 2>&1; then
                msg_wt_remove_branch_kept "$branch" >&2
            fi
            ;;
    esac

    # Land hygiene 2: a nested slug (auth/refresh-token) leaves empty parent
    # dirs under .worktrees/ after removal. Remove them up to (not including)
    # .worktrees itself.
    local parent
    parent=$(dirname "$wt")
    while [ "$parent" != "$main_root/.worktrees" ] && [ "$parent" != "$main_root" ] && [ "$parent" != "/" ]; do
        rmdir "$parent" 2>/dev/null || break
        parent=$(dirname "$parent")
    done
}

main() {
    # The directory the caller ran this from, before the cd below. land reads
    # it to refuse a caller that stands in the worktree it would remove.
    WT_CALLER_PWD="$PWD"
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    [ -n "$root" ] || root="${CLAUDE_PROJECT_DIR:-$PWD}"
    cd "$root" || return 1
    local sub="${1:-}"; shift || true
    case "$sub" in
        add)      cmd_add "$@" ;;
        landable) cmd_landable "$@" ;;
        verify)   cmd_verify "$@" ;;
        review-scope) cmd_review_scope "$@" ;;
        governed) cmd_governed "$@" ;;
        land)     cmd_land "$@" ;;
        remove)   cmd_remove "$@" ;;
        landed)   cmd_landed "$@" ;;
        sync)     cmd_sync "$@" ;;
        release)  cmd_release "$@" ;;
        status)   cmd_status "$@" ;;
        grant)    cmd_grant "$@" ;;
        attest)   cmd_attest "$@" ;;
        *) msg_wt_usage >&2; return 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
