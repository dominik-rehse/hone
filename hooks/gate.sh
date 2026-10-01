#!/bin/bash
# Stop-hook gate (Claude Code). The mechanical verify law: the durable suite must
# be green. It runs the project's one test adapter (scripts/run-tests.sh) and,
# where the language has them, the optional type-check and lint adapters
# (scripts/typecheck.sh, scripts/lint.sh). Any failure BLOCKS the stop so the
# model fixes it before finishing the turn. It never disables a gate to proceed.
#
# Which tier runs depends on where the work sits:
#   - An uncommitted change to any durable path → the fast UNIT tier. src/ and
#     tests/ are the red-green inner loop, and the gate must stay cheap on every
#     turn or someone disables it. A dependency sweep dirties other durable paths
#     instead (the manifest, the lockfile, a tool config, wherever the project
#     lists them). It breaks the suite just as easily, so the same tier runs.
#   - Clean tree on a hone/<change> worktree branch (work committed, about to
#     land) → the full --ALL tier, including integration/e2e. This is the moment
#     a change is about to merge. So this tier catches an integration regression
#     that a green unit tier would miss, rather than trusting the run skill's
#     prose --all step. This is a BACKSTOP, not the authoritative pre-merge
#     check. The hooks.json timeout (600s) bounds a Stop hook. The harness kills
#     a suite that outruns the timeout, which then reads as a non-block, so the
#     gate fails OPEN. The authoritative --all runs inside `worktree.sh land`,
#     under the land lock, on the merge: that one gates the trunk and
#     publishes nothing on red. Keep the suite within the hook timeout to keep this backstop
#     meaningful.
#     A hone/<change> branch with no commit of its own (add just cut it) has
#     no change on it yet, so it counts as the next case.
#   - Clean tree on any other branch → nothing in flight, no-op. With one
#     exception: when this session was already blocked in a linked worktree of
#     this repository, the gate evaluates THAT worktree instead, with the same
#     tier rules. A Stop hook runs where the agent's shell sits, and the agent
#     moves that shell, so standing in the primary tree was a way out of a red
#     suite. See THE WORKING-DIRECTORY HOLE below.
#   - No git → the unit tier (the gate cannot tell what is in flight, and
#     adapter presence already scopes this to hone projects).
#
# The --ALL tier runs once per change BRANCH, not once per commit. A green run
# records the branch, and every later Stop on that branch skips the suite. A
# green `worktree.sh verify` records it the same way. The
# backstop's value is one early warning per change. It tells the model that this
# change breaks an integration test, while the change is still open. A re-run
# after each new commit re-verifies almost the same code, and it adds little.
# The repeats also cost the most. They hold the land lock, so they collide with
# each other and with lands. `worktree.sh land` re-runs --all on the merge
# and publishes nothing on red. So a regression that a later commit
# introduces still never reaches the trunk.
# (An adapter that expresses tier selection elsewhere, e.g. the Node template
# runs the project's own "test" script, treats --unit and --all alike. The
# escalation only matters where the adapter distinguishes tiers.)
#
# Without the adapter the gate is a no-op, so it never gates a project that has
# not adopted hone. .hone-off disables it entirely. Type-check and lint are
# opt-in by their script existing. Tests are the minimum.
#
# Mechanism: a Stop hook may return {"decision":"block","reason":...} to keep
# the turn going, and the harness feeds the reason back to the model. On green
# it returns {"systemMessage":...} naming the checks that ran, so the
# transcript records that the gate fired (silence would be indistinguishable
# from a skip).
#
# THE BLOCK CAP. Some suites cannot go green: a test can contradict the spec it
# claims to check, and the right answer is then to stop and report, not to edit
# the test. The gate used to block that turn end forever. The harness overrides
# a Stop hook after 8 consecutive blocks and ends the session there, which
# leaves the run no turn in which to report. Runs of the 2026-09-19 probe ended
# exactly that way, and the person got a Plan and no report at all.
#
# So the gate caps itself first, at HONE_GATE_BLOCK_CAP (3). It counts only
# IDENTICAL failures: same step, same exit code, same output. A run that moves
# what the suite prints is working, and it keeps every block it earns.
#
# The cap ends in two steps. The Nth identical failure blocks once more and
# asks for the final report in that turn. The next one does not block, and the
# gate prints one line for the person. So the last turn holds a report, rather
# than whatever the run happened to be saying when the gate let go.
#
# THE WORKING-DIRECTORY HOLE. The counter also gives the gate a memory of
# where it blocked, which closes the way out that a `cd` used to offer. On the
# clean-tree, non-change-branch branch alone, the gate looks for a linked
# worktree whose counter carries this session's id. Where it finds one, it
# changes directory there first, so the suite, the receipt, and the lock all
# follow the tree under test. A session that was never blocked finds no
# counter and takes the old path, and a shell with work in flight where it
# stands never reaches the lookup.
#
# The cap loosens nothing. The gate is a Stop hook and gates no merge.
# `worktree.sh land` re-runs --all under the land lock on the merge and
# publishes nothing on red, so a red change still reaches no trunk. No
# message the agent reads before the cap mentions it, because a message that
# names a way past a gate is a way past the gate.
#
# A nested review session (`claude -p "/code-review ..."`, started by the run
# skill) skips the gate at once. It owns no change to verify.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/messages.sh"

# A nested review session (the run skill's `claude -p "/code-review ..."`)
# owns no change. The gate there ran the full suite and held the suite lock
# while the run waited on the review. See hone_nested_review.
hone_nested_review && exit 0

# The Stop payload, for the session id alone. The cap counts within one
# session, so a new session starts at zero. A payload without one (a direct
# call, an older harness) counts under a fixed name, which keeps the cap
# working for a single session and merges two concurrent ones.
STOP_INPUT=$(cat 2>/dev/null)
SESSION=$(hone_extract_top_field "$STOP_INPUT" session_id)
[ -n "$SESSION" ] || SESSION=no-session

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0

[ -f ".hone-off" ] && exit 0

ADAPTER="scripts/run-tests.sh"
[ -f "$ADAPTER" ] || exit 0   # no hone test adapter, so the gate skips this project

# Print "yes" when the working tree carries an uncommitted change to a durable
# path. hone_is_durable owns the perimeter: src/ tests/ docs/ db/ scripts/, the
# policy files, plus every .hone-durable-paths entry. So the gate, the guard,
# and the dirty-guard can never protect different sets.
#
# This used to read `git status --porcelain -- src tests`, which no-opped on a
# dependency sweep. `bun update` left package.json, the lockfile, and a tool
# config dirty, all three listed in that project's .hone-durable-paths, while
# src/ and tests/ stayed clean. The gate skipped the turn, and the lint was red.
# Dirt outside src/ breaks the suite just as well, so the suite runs.
#
# docs/-only dirt triggers the suite too. The unit tier plus type-check and
# lint is cheap, and one rule the reader can state beats an exception list.
gate_durable_dirt() {
    local entry xy path expect_orig=0
    while IFS= read -r -d '' entry; do
        if [ "$expect_orig" -eq 1 ]; then
            path="$entry"; expect_orig=0
        else
            xy="${entry:0:2}"
            case "$xy" in *R*|*C*) expect_orig=1 ;; esac
            path="${entry:3}"
        fi
        [ -n "$path" ] || continue
        hone_is_durable "$path" && { echo yes; return 0; }
    done < <(git --no-optional-locks status --porcelain -z 2>/dev/null)
}

# Pick the tier by what is in flight in the tree at $PWD. It sets TIER and
# BRANCH, and it returns 1 when this tree has nothing to verify.
gate_pick_tier() {
    BRANCH=""
    if [ -n "$(gate_durable_dirt)" ]; then
        TIER="--unit"                       # red-green in flight → fast tier
        return 0
    fi
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    case "$BRANCH" in
        hone/*)
            # A branch that add just cut holds no commit of its own, so no
            # change exists yet. A full suite there verified the trunk and
            # wrote a receipt that later read "already passed".
            hone_branch_fresh && return 1
            TIER="--all"; return 0 ;;       # committed on a change branch → full pre-land check
    esac
    return 1                                # clean, not a change branch
}

# The working-directory hole. A Stop hook runs where the agent's shell sits,
# and the agent moves that shell. A run blocked in its worktree could end the
# turn by standing in the primary tree, which is clean and on the trunk, so
# the gate read it as nothing in flight and no-opped. Two lab runs of
# 2026-09-19 left a red suite that way, and the cap never fired.
#
# The counter file is this session's memory of where it was blocked. So print
# the linked worktree that holds it. Another session's counter never matches,
# and a worktree that is gone is not in the list.
gate_blocked_worktree() {
    local wt dir mine line
    mine=$(git rev-parse --absolute-git-dir 2>/dev/null)
    while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        dir=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) || continue
        [ "$dir" = "$mine" ] && continue
        line=$(cat "$dir/hone-gate-blocks" 2>/dev/null) || continue
        case "$line" in "$SESSION "*) printf '%s\n' "$wt"; return 0 ;; esac
    done < <(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    return 1
}

# A bare Q&A turn on a clean, non-change tree has nothing to verify and exits
# early. The redirect sits on that one branch alone, so a session that was
# never blocked takes the path it always took. A shell that has work in flight
# where it stands never reaches it either, so no run is dragged out of the
# worktree it is working in.
TIER="--unit"
BRANCH=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    if ! gate_pick_tier; then
        REDIRECT=$(gate_blocked_worktree) || exit 0
        cd "$REDIRECT" || exit 0
        PROJECT_ROOT="$REDIRECT"
        [ -f ".hone-off" ] && exit 0
        [ -f "$ADAPTER" ] || exit 0
        gate_pick_tier || exit 0
    fi
fi

# $1 = a template from messages.sh (already prefixed).
block() { hone_stop_block "$1"; exit 0; }

# The counter of the block cap: one line, "<session> <signature> <count>", in
# <git-dir>/hone-gate-blocks, beside the green receipt. --git-dir resolves to
# .git/worktrees/<name> in a linked worktree, so a run that stays in its own
# worktree keeps a count of its own, and a second run in another worktree
# cannot spend it. The file sits inside .git, so it never dirties the tree and
# no project has to ignore it. Without a git dir the count goes under TMPDIR,
# keyed by the project root.
GATE_BLOCK_CAP="${HONE_GATE_BLOCK_CAP:-3}"
gate_blocks_file() {
    local dir
    dir=$(git rev-parse --git-dir 2>/dev/null)
    if [ -n "$dir" ]; then
        printf '%s/hone-gate-blocks' "$dir"
    else
        printf '%s/hone-gate-blocks-%s' "${TMPDIR:-/tmp}" \
            "$(printf '%s' "$PROJECT_ROOT" | cksum | tr -dc '0-9')"
    fi
}

# What makes two failures the same failure: the step, its exit code, and its
# output with every run of digits collapsed to '#'. A runner prints a duration,
# a port, a timestamp, or a process id beside the failure, and those move on
# every run while the failure does not. The price is that a change which moves
# only a number reads as no change. A run that is getting somewhere moves a
# test name or a line of prose too, and that resets the count.
gate_signature() {
    printf '%s|%s|%s' "$1" "$2" "$(printf '%s' "$3" | tr -s '0-9' '#')" | cksum | tr -dc '0-9'
}

# The cap ends in two steps, so that the last turn is a report by
# construction. A turn the gate simply released caught the run with nothing
# left to say: one lab run of 2026-09-19 signed off with "nothing new to add",
# and that sentence was the whole of what the person read.
#
#   failure 1 .. N-1   block, msg_gate_step_failed, no word of the cap
#   failure N          block, msg_gate_report_now: write the report in this
#                      turn, because the gate lets the next turn end
#   failure N+1        no block, msg_gate_cap_reached for the person
#
# The agent hears of the cap in the one turn where it can act on it, and never
# before, so no run can plan around it. A green run or a failure that changes
# clears the streak at any point, so a run that keeps working keeps every
# block it earns, and giving up sooner buys a run nothing.
#
# $4, when given, is the ordinary block's message in place of
# msg_gate_step_failed. The suite-lock wait passes its own, so a run that
# waits on its own background land meets the same cap as a red check.
gate_block_or_cap() {
    local label="$1" rc="$2" tail="$3" first="${4:-}" file sig n=1 recorded msg
    file=$(gate_blocks_file)
    sig=$(gate_signature "$label" "$rc" "$tail")
    recorded=$(cat "$file" 2>/dev/null)
    case "$recorded" in
        "$SESSION $sig "*) n=$(( ${recorded##* } + 1 )) ;;
    esac
    # A lock wait ran no suite, so its cap messages must not call it red.
    if [ "$n" -gt "$GATE_BLOCK_CAP" ]; then
        rm -f "$file" 2>/dev/null
        if [ "$rc" = lock ]; then msg=$(msg_gate_lock_cap_reached "$n")
        else msg=$(msg_gate_cap_reached "$label" "$n"); fi
        printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$msg")"
        exit 0
    fi
    printf '%s %s %s\n' "$SESSION" "$sig" "$n" > "$file" 2>/dev/null || true
    if [ "$n" -eq "$GATE_BLOCK_CAP" ]; then
        [ "$rc" = lock ] && block "$(msg_gate_lock_report_now "$n")"
        block "$(msg_gate_report_now "$label" "$n")"
    fi
    [ -n "$first" ] && block "$first"
    block "$(msg_gate_step_failed "$label" "$rc" "$tail")"
}

# A green turn ends the streak. The next red failure starts at one.
gate_clear_blocks() { rm -f "$(gate_blocks_file)" 2>/dev/null || true; }

# The green receipt for the full tier: one line,
# "<plugin version> <branch> <tree> <who>", in <git-dir>/hone-gate-green.
# `hone_gate_receipt_write` in common.sh writes it. The tree is the state of
# the whole working tree, uncommitted files included (hone_tree_state). The
# writer is `gate`, or `verify` when `worktree.sh verify` ran the suite green.
# A green verify counts, so a run that verified and then waits on a person
# does not pay for a second full suite at its next Stop.
#
# The SKIP key is the version and the branch. The full tier runs once per
# change branch, as the header says. The tree decides what the skip may
# claim: "on this tree" when it matches, "at an earlier tree" when a later
# commit moved it. --git-dir resolves to .git/worktrees/<name> in a linked
# worktree, so each worktree keeps its own receipt. The version makes a
# plugin upgrade a miss. A line that an older gate wrote has too few fields,
# so it misses too, and the suite runs one more time.
#
# No receipt comes from a fresh branch. Its tree is the trunk's, and a
# receipt there said "already passed" before the change existed.
#
# A receipt from verify covers the test suite alone. So on such a skip the
# gate still runs the optional type-check and lint adapters. They are not
# load-sensitive, so they need no lock.
#
# An untracked input that git ignores (a dependency install) can change the
# result without changing the tree. The gate accepts that gap, the same way
# it accepts the 600s hook timeout: land re-verifies authoritatively.
#
# The unit tier stays unmemoized. It runs on a dirty tree, and it is cheap
# by design.
GATE_RECEIPT=""
if [ "$TIER" = "--all" ] && [ -n "$BRANCH" ]; then
    GATE_RECEIPT="$(git rev-parse --git-dir 2>/dev/null)/hone-gate-green"
    read -r r_version r_branch r_tree r_by _ 2>/dev/null <"$GATE_RECEIPT"
    if [ -n "${r_by:-}" ] && [ "$r_version" = "$(hone_plugin_version)" ] \
       && [ "$r_branch" = "$BRANCH" ]; then
        if [ "$r_tree" = "$(hone_tree_state)" ]; then cached_at=same; else cached_at=earlier; fi
        cached_ran=""
        if [ "$r_by" = verify ]; then
            for step in typecheck lint; do
                [ -f "scripts/$step.sh" ] || continue
                out=$(bash "scripts/$step.sh" 2>&1); rc=$?
                label=$step; [ "$step" = typecheck ] && label=type-check
                if [ "$rc" -ne 0 ]; then
                    gate_block_or_cap "$label" "$rc" "$(printf '%s\n' "$out" | hone_fail_excerpt 15)"
                fi
                cached_ran+="${cached_ran:+, }$label"
            done
        fi
        gate_clear_blocks
        printf '{"systemMessage":"%s"}\n' \
            "$(hone_json_escape "$(msg_gate_green_cached "$r_tree" "$cached_at" "$r_by" "$cached_ran")")"
        exit 0
    fi
fi

# Run an adapter, capturing a short tail of its output for the block reason.
# On success, append the label to the green receipt.
ran=""
run_step() {
    local label="$1"; shift
    local out rc
    out=$("$@" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        local tail
        tail=$(printf '%s\n' "$out" | hone_fail_excerpt 15)
        gate_block_or_cap "$label" "$rc" "$tail"
    fi
    ran+="${ran:+, }$label"
}

# The full tier shares land's lock (<git-common-dir>/hone-land.lock). e2e tiers
# are load-sensitive, so a --all racing another suite or a land's re-verify
# poisons both signals (phantom flakes, spurious land reds). Short wait
# only: if a suite is live, blocking the stop with "retry" beats running red
# under contention. The unit tier stays lock-free: it is the per-Stop inner
# loop and must stay cheap. Without flock, degrade to running unserialized
# rather than not at all.
#
# The holder is often this session's own land or verify, run in the
# background as the run skill asks. So the block names no other session, and
# it counts toward the cap like a red check. It used to call block directly:
# about twenty field blocks said "another session" of the run's own land, and
# runs waiting on it looped on empty turns with no cap to end them.
#
# The gate queues for the lock like every other taker (hone_suite_lock), so
# it never overtakes a land that waits. A lock file it cannot open leaves
# the suite unserialized, as without flock.
if [ "$TIER" = "--all" ] && command -v flock >/dev/null 2>&1; then
    SUITE_LOCK="$(git rev-parse --git-common-dir 2>/dev/null)/hone-land.lock"
    hone_suite_lock "$SUITE_LOCK" "${HONE_SUITE_LOCK_TIMEOUT:-30}" suite
    [ $? -eq 5 ] && gate_block_or_cap "the wait for the suite lock" lock "" "$(msg_gate_suite_lock)"
fi

run_step "tests ($TIER)" bash "$ADAPTER" "$TIER"
[ -f "scripts/typecheck.sh" ] && run_step "type-check" bash "scripts/typecheck.sh"
[ -f "scripts/lint.sh" ] && run_step "lint" bash "scripts/lint.sh"

# Record the branch and the verified tree, so every later Stop on this branch
# skips the suite. Only after every step went green, and only for the full tier.
[ "$TIER" = "--all" ] && hone_gate_receipt_write gate

# Every step went green, so no failure is repeating. The cap starts over.
gate_clear_blocks

# Green receipt: one visible line saying what actually ran, so a transcript can
# confirm the gate fired rather than inferring it from silence.
printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$(msg_gate_green "$ran")")"
exit 0
