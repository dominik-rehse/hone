#!/bin/bash
# Every message hone prints, in one place. SOURCED by the hooks (guard.sh,
# bash-guard.sh, gate.sh, nag.sh, session-start.sh) and by the scripts that
# print to a human (scripts/worktree.sh, scripts/setup.sh). Defines functions
# only; no side effects at source time.
#
# Shape. A human-facing message is three lines:
#
#   line 1  what happened, one sentence, ending in a period
#   line 2  Do: one command or one concrete action
#   line 3  Why: ten words or fewer (optional)
#
# A paste block (a rules list, a diffstat, a log tail) follows those lines,
# indented by two spaces. An agent-facing deny or block keeps the same order,
# verdict first and reason last, but its reason may run to a full sentence,
# because that reason is what steers the model.
#
# All prose follows Simplified Technical English: 25 words or fewer per
# sentence, one idea per sentence, active voice, no semicolons, plain words.
# Commands, paths, and identifiers inside a message are never reworded.
#
# Executed directly, this file prints its own templates:
#
#   bash hooks/messages.sh --dump   Markdown, for the ste lint (test/run.sh)
#   bash hooks/messages.sh --raw    plain text, for the shape check
#
# Both walk hone_msg_catalog, which names every template once with placeholder
# arguments, so a template that nobody registers is never linted and a template
# that nobody prints is never kept alive by the catalog alone.

# Indent a multi-line value as a paste block. Empty input prints nothing.
hone_msg_block() {
    [ -n "$1" ] || return 0
    printf '%s\n' "$1" | sed 's/^/  /'
}

# ---------------------------------------------------------------- guard

msg_guard_no_file_path() {
    cat <<'EOF'
hone guard: the Write or Edit input carried no tool_input.file_path.
Do: retry the tool call with an explicit file_path.
Why: the guard cannot check a write it cannot see, so it denies it.
EOF
}

msg_guard_signoff() {
    local rel="$1"
    cat <<EOF
hone guard: $rel is a human sign-off for a land gate.
Do: escalate to the human and wait for them.
Why: the agent never writes a grant or a proof sign-off, by any route. The human runs worktree.sh grant or attest in their own terminal.
EOF
}

msg_guard_primary_tree() {
    local rel="$1"
    cat <<EOF
hone guard: $rel is a protected path in the primary tree.
Do: make the change in a worktree and let land merge it back.
Why: the primary tree only receives merges. /hone:run creates the worktree. For a quick manual edit, the human can create .hone-off and delete it after.
EOF
}

msg_guard_no_test() {
    local rel="$1" base="$2" feature="$3"
    cat <<EOF
hone guard: $rel has no test.
Do: write $base.test.<ext> or tests/$feature.test.<ext>, watch it fail, then write the code.
Why: hone is test-first, so the failing test comes before the code it proves.
EOF
}

# ----------------------------------------------------------- bash-guard

msg_bashguard_unparsed() {
    cat <<'EOF'
hone bash-guard: the command did not parse, and the payload carries a gate-sabotage token.
Do: review the command by hand before you allow it.
Why: tokens such as --no-verify, core.hooksPath, and .hone-off turn the hone gate off.
EOF
}

msg_bashguard_sabotage() {
    cat <<'EOF'
hone bash-guard: this command would disable the hone gate.
Do: leave the gate on and finish the work with it.
Why: --no-verify, core.hooksPath, and creating .hone-off all switch enforcement off. If you intend this change, make it yourself outside the agent.
EOF
}

msg_bashguard_signoff() {
    cat <<'EOF'
hone bash-guard: this command would write an authority grant or a proof sign-off.
Do: escalate to the human and wait for them to run it.
Why: .hone-grant/, .hone-proof/, and the worktree.sh grant and attest helpers belong to the human alone.
EOF
}

msg_bashguard_protected() {
    cat <<'EOF'
hone bash-guard: this command modifies a protected hone artifact.
Do: confirm you intend this change before you allow it.
Why: the test adapter, the hooks, the settings, and the policy files carry hone's enforcement.
EOF
}

msg_bashguard_head_move() {
    cat <<'EOF'
hone bash-guard: this command moves HEAD in the primary tree.
Do: investigate in a scratch tree from 'git worktree add --detach' instead.
Why: the primary tree stays on the trunk as a merge target for every session. Landing goes through worktree.sh land, which serializes the merge.
EOF
}

# ----------------------------------------------------------------- gate

msg_gate_step_failed() {
    local label="$1" rc="$2" tail="$3"
    cat <<EOF
hone gate: $label failed with exit $rc.
Do: fix the failure before you finish the turn.
Why: the durable suite must be green at the end of a turn. Never disable a check to get through.
Output tail:
$(hone_msg_block "$tail")
EOF
}

msg_gate_suite_lock() {
    cat <<'EOF'
hone gate: another session is running the full suite.
Do: wait for that run to finish, then verify again.
Why: two full suites at once poison each other's signal. Do not run the suite concurrently.
EOF
}

msg_gate_green() {
    printf 'hone gate: green (%s)\n' "$1"
}

# ------------------------------------------------------------------ nag

msg_nag_header() {
    printf 'hone nag (advisory):\n'
}

msg_nag_plan_survived() {
    local plan="$1" evidence="$2"
    cat <<EOF
$plan survived its landing ($evidence).
Do: delete the Plan.
Why: consolidate deletes a landed Plan, and git keeps it.
EOF
}

msg_nag_plans_pending() {
    local n="$1"
    cat <<EOF
$n Plan(s) pending run in .plans/.
Do: run /hone:run to pick them up.
Why: a queued Plan is normal, not a problem.
EOF
}

msg_nag_note_oversized() {
    local note="$1" lines="$2" cap="$3"
    cat <<EOF
$note is $lines lines, over the $cap-line cap.
Do: cut it, or push the detail into types, Decisions, or tests.
Why: a Note is a map plus one invariant.
EOF
}

msg_nag_note_orphan() {
    local note="$1" area="$2"
    cat <<EOF
$note has no src/$area/ directory beside it.
Do: rename the Note to its area, or delete it if the area is gone.
Why: a Note is 1:1 with an existing area.
EOF
}

msg_nag_governs_broken() {
    local doc="$1" path="$2"
    cat <<EOF
$doc declares Governs: $path, which no longer exists.
Do: update the reference, or cut the doc if the code is gone.
Why: this durable doc has drifted from its code.
EOF
}

msg_nag_no_deletions() {
    local ins="$1" target="$2"
    cat <<EOF
This change deletes nothing (+$ins/-0 against $target).
Do: cut a redundant test, dead code, or a stale doc line.
Why: every cycle removes something.
EOF
}

msg_nag_merged_branch() {
    local branch="$1"
    cat <<EOF
Branch $branch is fully merged and has no worktree.
Do: delete it with 'git branch -d $branch'.
Why: land retires a branch with its worktree.
EOF
}

msg_nag_memory_project() {
    local file="$1" dir="$2"
    cat <<EOF
$file is a 'type: project' harness memory in $dir.
Do: land it as a Decision or a Note through consolidate.
Why: that store is per-user, uncommitted, and invisible to garden.
EOF
}

# --------------------------------------------------------- session-start

msg_session_no_adapter() {
    cat <<'EOF'
hone: this project has no scripts/run-tests.sh, so the gate has no suite to run.
Do: run bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
Why: the gate runs the project's test adapter.
EOF
}

msg_session_no_src() {
    cat <<'EOF'
hone: this project has no src/ directory, so the guard, gate, and nag do nothing.
Do: put code under src/<area>/, or run scripts/setup.sh to create it.
Why: hone keys its enforcement off that layout.
EOF
}

msg_session_missing_deny() {
    local missing="$1"
    cat <<EOF
hone: .claude/settings.json is missing these deny rules, so part of the file-tool tamper resistance is off.
Do: paste the rules below into permissions.deny.
Why: they keep the file tools off the adapters.
$(hone_msg_block "$missing")
EOF
}

# ---------------------------------------------------------------- setup

msg_setup_cannot_enter() {
    local dir="$1"
    cat <<EOF
hone setup: cannot enter $dir.
Do: check that the path exists, then run setup again.
Why: setup writes inside the project directory.
EOF
}

msg_setup_header() {
    printf 'hone setup in %s\n' "$1"
}

msg_setup_no_ecosystem() {
    local templates="$1"
    cat <<EOF
hone setup: could not detect the ecosystem, so it installed no test adapter.
Do: author scripts/run-tests.sh against the contract below.
Why: /hone:setup does this step for you.
$(hone_msg_block "$templates")
EOF
}

msg_setup_adapter_exists() {
    local template="$1"
    cat <<EOF
hone setup: scripts/run-tests.sh already exists, so setup left it alone.
Do: diff it against the current template if you want the newer one.
Why: setup never overwrites an adapter you own.
$(hone_msg_block "diff scripts/run-tests.sh $template")
EOF
}

msg_setup_adapter_installed() {
    printf 'hone setup: installed scripts/run-tests.sh (from %s).\n' "$1"
}

msg_setup_gitignore_pruned() {
    printf 'hone setup: removed %s from .gitignore (tracked or retired in this hone version).\n' "$1"
}

msg_setup_gitignore_ok() {
    printf 'hone setup: gitignored the per-developer artifacts.\n'
}

msg_setup_docs_created() {
    printf 'hone setup: created docs/decisions, docs/notes, docs/open-questions.md, .plans/, and src/.\n'
}

msg_setup_missing_deny() {
    local missing="$1"
    cat <<EOF
hone setup: .claude/settings.json is missing these deny rules.
Do: paste the rules below into permissions.deny.
Why: add them after you verify the adapters they protect.
$(hone_msg_block "$missing")
EOF
}

msg_setup_deny_complete() {
    printf 'hone setup: the settings deny rules are complete.\n'
}

msg_setup_layout() {
    printf 'hone setup: code lives under src/<area>/, where the guard, gate, and nag apply.\n'
}

msg_setup_proof_hint() {
    local templates="$1"
    cat <<EOF
hone setup: a change that needs real-environment proof also needs scripts/proof.sh.
Do: copy a template from the directory below into scripts/proof.sh.
Why: the land proof gate runs that adapter.
$(hone_msg_block "$templates")
EOF
}

msg_setup_done() {
    cat <<'EOF'
hone setup: done.
Do: author a change with /hone:plan, then run /hone:run.
EOF
}

# ------------------------------------------------------------- worktree

msg_wt_usage() {
    printf '%s\n' 'usage: worktree.sh {add <change>|landable|verify|land <change>|remove <worktree-path>|status|grant <change> "who/why"|attest <change> "what you ran"}'
}

msg_wt_grant_usage() {
    printf '%s\n' 'usage: worktree.sh grant <change> "who/why"'
}

msg_wt_attest_usage() {
    printf '%s\n' 'usage: worktree.sh attest <change> "what you ran"'
}

msg_wt_not_a_repo() {
    cat <<'EOF'
hone worktree: this directory is not a git repository.
Do: run the command inside the project's git repository.
Why: every subcommand reads git state.
EOF
}

msg_wt_needs_change() {
    local sub="$1"
    cat <<EOF
hone worktree: $sub needs a change name.
Do: run 'worktree.sh $sub <change>'.
Why: the change name selects the branch.
EOF
}

msg_wt_add_path_claimed() {
    local path="$1"
    cat <<EOF
hone worktree: $path already exists, and that worktree claims this change.
Do: resume that worktree by hand, or pick another change.
Why: another run owns it, or it is leftover evidence.
EOF
}

msg_wt_add_branch_claimed() {
    local branch="$1"
    cat <<EOF
hone worktree: branch $branch already exists, and that branch claims this change.
Do: resume that branch by hand, or pick another change.
Why: another run owns it, or it is leftover evidence.
EOF
}

msg_wt_add_race() {
    local branch="$1"
    cat <<EOF
hone worktree: a concurrent run just claimed $branch.
Do: skip this change and let that run finish it.
Why: the branch ref is the claim, and it is atomic.
EOF
}

msg_wt_add_failed() {
    cat <<'EOF'
hone worktree: 'git worktree add' failed.
Do: read git's error above, fix the repository state, then retry.
Why: hone could not create the worktree.
EOF
}

msg_wt_landable_none() {
    local target="$1"
    cat <<EOF
hone worktree: no worktree is ahead of $target.
Do: commit work on a change branch before you land.
Why: land needs a branch with new commits.
EOF
}

msg_wt_no_adapter() {
    cat <<'EOF'
hone worktree: this tree has no scripts/run-tests.sh adapter.
Do: run scripts/setup.sh to install the test adapter.
Why: verify runs the project's test adapter.
EOF
}

msg_wt_no_flock() {
    local action="$1"
    cat <<EOF
hone worktree: flock is missing, so hone cannot serialize the $action across sessions.
Do: install util-linux, then retry.
Why: two full suites at once poison each other's signal.
EOF
}

msg_wt_lock_unopenable() {
    local lock="$1"
    cat <<EOF
hone worktree: cannot open the lock file at $lock.
Do: check the permissions on that path, then retry.
Why: land and verify serialize on that one lock.
EOF
}

msg_wt_lock_timeout() {
    local timeout="$1"
    cat <<EOF
hone worktree: another session held the lock for more than $timeout seconds.
Do: wait for that run to finish, then retry.
Why: a land or a full-suite run holds the lock.
EOF
}

msg_wt_land_no_branch() {
    local branch="$1"
    cat <<EOF
hone worktree: branch $branch does not exist, so there is nothing to land.
Do: create the change with 'worktree.sh add <change>' and commit on it.
Why: land merges an existing change branch.
EOF
}

msg_wt_land_detached() {
    cat <<'EOF'
hone worktree: the primary tree is in detached HEAD.
Do: check the trunk out in the primary tree, then retry.
Why: land merges the change into the trunk.
EOF
}

msg_wt_land_authority_missing() {
    local branch="$1" reasons="$2" diffstat="$3" review_cmd="$4" grant_cmd="$5"
    cat <<EOF
hone worktree: $branch is an irreversible change with no authority grant.
Do: review the diff, then record who authorized it and why.
Why: land stopped before the merge and kept the worktree.
Signals:
$(hone_msg_block "$reasons")
Diffstat:
$(hone_msg_block "$diffstat")
Review the change:
$(hone_msg_block "$review_cmd")
Record the grant, then re-run land:
$(hone_msg_block "$grant_cmd")
EOF
}

msg_wt_land_grant_empty() {
    local change="$1" grant_cmd="$2"
    cat <<EOF
hone worktree: .hone-grant/$change is empty, so it authorizes nothing.
Do: rewrite it with the command below, then re-run land.
Why: the grant text is the audit trail in history.
$(hone_msg_block "$grant_cmd")
EOF
}

# The declared check, as a labelled paste block. A `Proof: real-environment`
# trailer carries the check after a dash, so the gate can name the exact thing
# the human must run. A bare trailer (an older Plan) prints nothing here, and
# the message keeps its generic wording.
hone_msg_proof_check() {
    [ -n "$1" ] || return 0
    printf 'The Plan declares this check:\n'
    hone_msg_block "$1"
}

# The bootstrap case, as a labelled paste block. land runs the PRIMARY tree's
# proof.sh, so the change that writes or edits that adapter cannot be proven by
# it: the copy land would run is the one this change replaces. $1 is the change
# name, empty when the change leaves the adapter alone.
hone_msg_proof_bootstrap() {
    [ -n "$1" ] || return 0
    cat <<'EOF'
This change edits scripts/proof.sh or its probes, so land cannot use the copy it has.
Run the change's own adapter, from its worktree, in your own terminal:
EOF
    hone_msg_block "bash scripts/proof.sh $1"
}

msg_wt_land_proof_adapter_failed() {
    local branch="$1" check="$2" attest_cmd="$3" bootstrap="$4"
    cat <<EOF
hone worktree: $branch declares real-environment proof, and scripts/proof.sh failed.
Do: read the adapter output above, fix the change, then land again.
Why: the real environment refused this change.
EOF
    hone_msg_proof_check "$check"
    if [ -n "$bootstrap" ]; then
        hone_msg_proof_bootstrap "$bootstrap"
        printf 'Record that run, then re-run land:\n'
        hone_msg_block "$attest_cmd"
    fi
    printf 'land kept the worktree as evidence.\n'
}

msg_wt_land_proof_signoff_stale() {
    local change="$1" branch="$2" tip="$3" check="$4" attest_cmd="$5" bootstrap="$6"
    cat <<EOF
hone worktree: .hone-proof/$change names no commit, or an older one, so it cannot cover $branch at $tip.
Do: run the check against this tip, then record the sign-off again.
Why: a sign-off covers one commit, never a later one.
EOF
    hone_msg_proof_check "$check"
    hone_msg_proof_bootstrap "$bootstrap"
    printf 'Record the new sign-off, then re-run land:\n'
    hone_msg_block "$attest_cmd"
    printf 'land kept the worktree as evidence.\n'
}

msg_wt_land_proof_missing() {
    local branch="$1" check="$2" attest_cmd="$3" bootstrap="$4"
    cat <<EOF
hone worktree: $branch declares real-environment proof, which the test suite cannot give.
Do: run the check yourself, then record your sign-off.
Why: a green suite proves assertions, not deployed behaviour.
EOF
    hone_msg_proof_check "$check"
    hone_msg_proof_bootstrap "$bootstrap"
    printf 'Record your sign-off, then re-run land:\n'
    hone_msg_block "$attest_cmd"
    [ -n "$bootstrap" ] || printf 'The other route is scripts/proof.sh in the primary tree, a real check such as a journey, a canary, or deployed health.\n'
    printf 'land kept the worktree as evidence.\n'
}

msg_wt_land_proof_always_no_adapter() {
    local templates="$1"
    cat <<EOF
hone worktree: .hone-proof-always asks land to prove every change, and scripts/proof.sh is missing.
Do: add the adapter, or delete the marker file.
Why: the marker promises a check this project does not have.
Copy a template from the directory below, then commit it:
$(hone_msg_block "$templates")
land kept the worktree as evidence.
EOF
}

msg_wt_land_conflict() {
    local branch="$1"
    cat <<EOF
hone worktree: merging $branch conflicted, so land restored the primary tree.
Do: fold this change in serially, then land it again.
Why: the independence check missed an overlap.
EOF
}

msg_wt_land_suite_red() {
    local branch="$1" log="$2" tail="$3"
    cat <<EOF
hone worktree: the suite failed in the primary tree after merging $branch.
Do: read the tail below, fix the regression, then land again.
Why: land rolled the merge back and kept the worktree.
Last lines of $log:
$(hone_msg_block "$tail")
EOF
}

msg_wt_land_tier_empty() {
    local tiers="$1"
    cat <<EOF
hone worktree: the suite went green, and these tiers ran no test at all.
Do: fix the adapter's tier selection, then run the suite again.
Why: an empty tier makes a green suite prove nothing.
Tiers that ran nothing:
$(hone_msg_block "$tiers")
land merged the change anyway, because this warning never blocks.
EOF
}

msg_wt_grant_recorded() {
    local change="$1"
    cat <<EOF
hone worktree: grant recorded at .hone-grant/$change.
Do: re-run land, or delete the file to revoke the grant.
Why: the grant text lands in the merge commit body.
EOF
}

msg_wt_attest_recorded() {
    local change="$1" tip="$2"
    cat <<EOF
hone worktree: sign-off recorded at .hone-proof/$change for commit $tip.
Do: re-run land.
Why: the sign-off stops counting after new commits.
EOF
}

msg_wt_attest_empty() {
    cat <<'EOF'
hone worktree: the sign-off text is empty, so it records nothing.
Do: run attest again with the check you ran and its outcome.
Why: the sign-off is the whole audit trail.
EOF
}

msg_wt_attest_placeholder() {
    local what="$1"
    cat <<EOF
hone worktree: the sign-off text is still the placeholder from the usage line.
Do: run attest again, and name the check you ran and its outcome.
Why: a placeholder tells a later reader nothing.
The text you passed:
$(hone_msg_block "$what")
EOF
}

msg_wt_attest_no_branch() {
    local change="$1"
    cat <<EOF
hone worktree: branch hone/$change does not exist, so there is nothing to attest.
Do: attest the change once its branch carries commits.
Why: a sign-off names the commit it proved.
EOF
}

msg_wt_remove_needs_path() {
    cat <<'EOF'
hone worktree: remove needs a worktree path.
Do: run 'worktree.sh remove <worktree-path>'.
Why: the path selects the worktree to retire.
EOF
}

msg_wt_remove_foreign() {
    local path="$1"
    cat <<EOF
hone worktree: $path is not under .worktrees/, so hone did not create it.
Do: remove it yourself if you own it.
Why: hone retires only the worktrees it made.
EOF
}

msg_wt_remove_self() {
    local path="$1"
    cat <<EOF
hone worktree: $path is the worktree you are standing in.
Do: run land from the primary tree instead.
Why: a worktree cannot remove itself.
EOF
}

msg_wt_remove_failed() {
    local path="$1"
    cat <<EOF
hone worktree: 'git worktree remove $path' failed.
Do: commit or discard the changes in that worktree, then retry.
Why: git refuses to remove a worktree with changes.
EOF
}

msg_wt_remove_branch_kept() {
    local branch="$1"
    cat <<EOF
hone worktree: hone kept branch $branch, which is not fully merged.
Do: delete it with 'git branch -D $branch' only if you abandon the work.
Why: an unmerged branch is evidence of unlanded work.
EOF
}

msg_status_header() {
    printf 'hone status (%s, primary on %s)\n' "$1" "$2"
}

msg_status_hooks_off() {
    printf -- '- hooks: OFF (.hone-off present, delete it to re-enable)\n'
}

msg_status_hooks_on() {
    printf -- '- hooks: on (guard, gate, nag, plus the land gates)\n'
}

msg_status_adapters() {
    printf -- '- adapters (scripts/<name>.sh):%s\n' "$1"
}

msg_status_policy() {
    printf -- '- policy: %s (%s entries, committed)\n' "$1" "$2"
}

msg_status_policy_uncommitted() {
    printf -- '- policy: %s (%s entries, NOT committed, and policy files are project config)\n' "$1" "$2"
}

msg_status_policy_legacy() {
    printf -- '  note: legacy name, rename it to .hone-irreversible-paths\n'
}

msg_status_proof_always() {
    printf -- '- proof: .hone-proof-always present (committed), land proves every change\n'
}

msg_status_proof_always_uncommitted() {
    printf -- '- proof: .hone-proof-always present, NOT committed, and policy files are project config\n'
}

msg_status_plan_pending() {
    printf -- '- plan pending: %s\n' "$1"
}

msg_status_plans_none() {
    printf -- '- plans: none pending\n'
}

msg_status_worktree() {
    printf -- '- worktree in flight: %s (%s)\n' "$1" "$2"
}

msg_status_worktrees_none() {
    printf -- '- worktrees: none in flight\n'
}

msg_status_grant() {
    printf -- '- grant: %s\n' "$1"
}

msg_status_signoff() {
    printf -- '- proof sign-off: %s\n' "$1"
}

msg_status_deny_present() {
    printf -- '- settings deny rules: present\n'
}

msg_status_deny_missing() {
    local missing="$1"
    printf -- '- settings deny rules: MISSING from the canonical set, add these from the README install block:\n'
    printf '%s\n' "$missing" | sed 's/^/    /'
}

# ---------------------------------------------------------------- catalog

# One line per template: section|kind|function|argument...
# kind is human (a person reads it), agent (a deny or a block the model reads),
# or plain (a receipt, a usage line, or one row of a status listing). human and
# agent templates carry the three-line shape the header describes; plain ones
# do not, and the shape check skips them.
hone_msg_catalog() {
    cat <<'CATALOG'
guard|agent|msg_guard_no_file_path
guard|agent|msg_guard_signoff|.hone-grant/<change>
guard|agent|msg_guard_primary_tree|src/<area>/<file>
guard|agent|msg_guard_no_test|src/<area>/<file>.<ext>|src/<area>/<file>|<area>/<file>
bash-guard|agent|msg_bashguard_unparsed
bash-guard|agent|msg_bashguard_sabotage
bash-guard|agent|msg_bashguard_signoff
bash-guard|agent|msg_bashguard_protected
bash-guard|agent|msg_bashguard_head_move
gate|agent|msg_gate_step_failed|<check>|<code>|<output-tail>
gate|agent|msg_gate_suite_lock
gate|plain|msg_gate_green|<checks that ran>
nag|plain|msg_nag_header
nag|human|msg_nag_plan_survived|.plans/<change>.md|<evidence>
nag|human|msg_nag_plans_pending|<count>
nag|human|msg_nag_note_oversized|docs/notes/<area>.md|<count>|<cap>
nag|human|msg_nag_note_orphan|docs/notes/<area>.md|<area>
nag|human|msg_nag_governs_broken|docs/decisions/<topic>.md|<path>
nag|human|msg_nag_no_deletions|<count>|<branch>
nag|human|msg_nag_merged_branch|hone/<change>
nag|human|msg_nag_memory_project|<file>.md|<memory-dir>
session-start|human|msg_session_no_adapter
session-start|human|msg_session_no_src
session-start|human|msg_session_missing_deny|<missing deny rule>
setup|human|msg_setup_cannot_enter|<project-dir>
setup|plain|msg_setup_header|<project-dir>
setup|human|msg_setup_no_ecosystem|<plugin-root>/templates/run-tests/README.md
setup|human|msg_setup_adapter_exists|<plugin-root>/templates/run-tests/<template>
setup|plain|msg_setup_adapter_installed|<template>
setup|plain|msg_setup_gitignore_pruned|<entry>
setup|plain|msg_setup_gitignore_ok
setup|plain|msg_setup_docs_created
setup|human|msg_setup_missing_deny|<missing deny rule>
setup|plain|msg_setup_deny_complete
setup|plain|msg_setup_layout
setup|human|msg_setup_proof_hint|<plugin-root>/templates/proof/
setup|human|msg_setup_done
worktree|plain|msg_wt_usage
worktree|plain|msg_wt_grant_usage
worktree|plain|msg_wt_attest_usage
worktree|human|msg_wt_not_a_repo
worktree|human|msg_wt_needs_change|<subcommand>
worktree|human|msg_wt_add_path_claimed|<main-root>/.worktrees/<change>
worktree|human|msg_wt_add_branch_claimed|hone/<change>
worktree|human|msg_wt_add_race|hone/<change>
worktree|human|msg_wt_add_failed
worktree|human|msg_wt_landable_none|<branch>
worktree|human|msg_wt_no_adapter
worktree|human|msg_wt_no_flock|<land or full suite>
worktree|human|msg_wt_lock_unopenable|<git-common-dir>/hone-land.lock
worktree|human|msg_wt_lock_timeout|<seconds>
worktree|human|msg_wt_land_no_branch|hone/<change>
worktree|human|msg_wt_land_detached
worktree|human|msg_wt_land_authority_missing|hone/<change>|- <signal>|<diffstat>|git -C <main-root> diff <base>...hone/<change>|bash <plugin-root>/scripts/worktree.sh grant <change> "who/why"
worktree|human|msg_wt_land_grant_empty|<change>|bash <plugin-root>/scripts/worktree.sh grant <change> "who/why"
worktree|human|msg_wt_land_proof_adapter_failed|hone/<change>|<the check the Plan declared>|bash <plugin-root>/scripts/worktree.sh attest <change> "what you ran and the outcome"   (stamps the tip commit)|<change>
worktree|human|msg_wt_land_proof_signoff_stale|<change>|hone/<change>|<tip>|<the check the Plan declared>|bash <plugin-root>/scripts/worktree.sh attest <change> "what you ran and the outcome"   (stamps the tip commit)|<change>
worktree|human|msg_wt_land_proof_missing|hone/<change>|<the check the Plan declared>|bash <plugin-root>/scripts/worktree.sh attest <change> "what you ran and the outcome"   (stamps the tip commit)|<change>
worktree|human|msg_wt_land_proof_always_no_adapter|<plugin-root>/templates/proof/
worktree|human|msg_wt_land_conflict|hone/<change>
worktree|human|msg_wt_land_suite_red|hone/<change>|<git-common-dir>/hone-land.log|<output-tail>
worktree|human|msg_wt_land_tier_empty|- <tier>
worktree|human|msg_wt_grant_recorded|<change>
worktree|human|msg_wt_attest_recorded|<change>|<tip>
worktree|human|msg_wt_attest_empty
worktree|human|msg_wt_attest_placeholder|what you ran
worktree|human|msg_wt_attest_no_branch|<change>
worktree|human|msg_wt_remove_needs_path
worktree|human|msg_wt_remove_foreign|<path>
worktree|human|msg_wt_remove_self|<path>
worktree|human|msg_wt_remove_failed|<path>
worktree|human|msg_wt_remove_branch_kept|hone/<change>
status|plain|msg_status_header|<main-root>|<branch>
status|plain|msg_status_hooks_off
status|plain|msg_status_hooks_on
status|plain|msg_status_adapters| run-tests=yes typecheck=no lint=no proof=no
status|plain|msg_status_policy|<policy-file>|<count>
status|plain|msg_status_policy_uncommitted|<policy-file>|<count>
status|plain|msg_status_policy_legacy
status|plain|msg_status_proof_always
status|plain|msg_status_proof_always_uncommitted
status|plain|msg_status_plan_pending|.plans/<change>.md
status|plain|msg_status_plans_none
status|plain|msg_status_worktree|<path>|<branch>
status|plain|msg_status_worktrees_none
status|plain|msg_status_grant|.hone-grant/<change>
status|plain|msg_status_signoff|.hone-proof/<change>
status|plain|msg_status_deny_present
status|plain|msg_status_deny_missing|<missing deny rule>
CATALOG
}

# Render one message as Markdown: prose stays prose, and a run of two-space
# indented lines becomes a fenced block, so the lint reads the prose and leaves
# the commands alone.
hone_msg_markdown() {
    awk '
        function close_fence() { if (fenced) { print "```"; print ""; fenced = 0 } }
        /^  / {
            if (!fenced) { print ""; print "```text"; fenced = 1 }
            sub(/^  /, ""); print; next
        }
        /^[[:space:]]*$/ { close_fence(); next }
        { close_fence(); print }
        END { close_fence() }
    '
}

# Walk the catalog, calling $1 with (kind, function, section) per entry.
hone_msg_walk() {
    local emit="$1" line
    local -a f
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        IFS='|' read -r -a f <<<"$line"
        "$emit" "${f[0]}" "${f[1]}" "${f[2]}" "${f[@]:3}"
    done < <(hone_msg_catalog)
}

hone_msg_emit_raw() {
    local section="$1" kind="$2" fn="$3"; shift 3
    printf '=== %s %s\n' "$fn" "$kind"
    "$fn" "$@"
    printf '\n'
}

HONE_MSG_SECTION=""
hone_msg_emit_markdown() {
    local section="$1" kind="$2" fn="$3"; shift 3
    if [ "$section" != "$HONE_MSG_SECTION" ]; then
        printf '## %s\n\n' "$section"
        HONE_MSG_SECTION="$section"
    fi
    printf '### %s\n\n' "$fn"
    "$fn" "$@" | hone_msg_markdown
    printf '\n'
}

hone_msg_dump() {
    cat <<'EOF'
# hone message templates

This file comes from `bash hooks/messages.sh --dump`. Every template appears
once, with angle brackets in place of the dynamic values. The suite lints this
file, so the prose here is the prose hone prints.

EOF
    hone_msg_walk hone_msg_emit_markdown
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        --dump) hone_msg_dump ;;
        --raw)  hone_msg_walk hone_msg_emit_raw ;;
        *) echo "usage: messages.sh {--dump|--raw}" >&2; exit 2 ;;
    esac
fi
