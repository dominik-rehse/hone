#!/bin/bash
# Stop-hook gate (Claude Code). The mechanical verify law: the durable suite must
# be green. It runs the project's one test adapter (scripts/run-tests.sh) and,
# where the language has them, the optional type-check and lint adapters
# (scripts/typecheck.sh, scripts/lint.sh). Any failure BLOCKS the stop so the
# model fixes it before finishing the turn. It never disables a gate to proceed.
#
# What it does depends on where the work sits:
#   - An uncommitted change to any durable path → the fast UNIT tier: tests
#     with --unit, then type-check and lint. src/ and tests/ are the red-green
#     inner loop. A dependency sweep dirties other durable paths instead (the
#     manifest, the lockfile, a tool config, wherever the project lists them).
#     It breaks the suite just as easily, so the same tier runs.
#   - Clean tree on a hone/<change> worktree branch (work committed, about to
#     land) → the FULL TIER. The gate runs no check here. It asks for the
#     result of `worktree.sh verify`. See THE FULL TIER below.
#     A hone/<change> branch with no commit of its own (add just cut it) has
#     no change on it yet, so it counts as the next case.
#   - Clean tree on any other branch → nothing in flight, no-op. With one
#     exception: when this session was already blocked in a linked worktree of
#     this repository, the gate evaluates THAT worktree instead, with the same
#     rules. A Stop hook runs where the agent's shell sits, and the agent
#     moves that shell, so standing in the primary tree was a way out of a red
#     suite. See THE WORKING-DIRECTORY HOLE below.
#   - No git → the unit tier (the gate cannot tell what is in flight, and
#     adapter presence already scopes this to hone projects).
#
# THE UNIT MEMO. A green unit tier records "<plugin version> <tree>" in
# <git-dir>/hone-gate-unit, where the tree is hone_tree_state: HEAD plus every
# uncommitted and untracked file. A later Stop with the same version and the
# same tree runs no step. Any change to the tree runs every step. A red step
# leaves no record. The unit tier is not cheap everywhere: in one project 358
# of 613 runs, at 51s each, followed a turn that changed no file.
# The key misses two kinds of input. A file that git ignores (node_modules,
# .env, generated code) can change a result without changing the tree, and
# the gate accepts that gap, as the full receipt does: land re-verifies on
# the merge. An edit inside a submodule changes no key either, so while any
# submodule holds uncommitted work the gate neither skips nor writes a memo.
#
# THE FULL TIER. `worktree.sh verify` runs the full suite, type-check, and lint
# under the suite lock that land shares. A green verify writes the receipt
# "<plugin version> <branch> <tree> verify" in <git-dir>/hone-gate-green
# (hone_gate_receipt_write). The gate reads it:
#   - A receipt for this version, branch, and the tree as it stands → the
#     turn ends, and no check runs.
#   - A receipt for this version and branch at an earlier tree → the unit
#     tier runs, with its memo, for the commits since verify. The receipt
#     covers the full suite once per branch, not each commit.
#   A verify removes the receipt before its first step, so a red verify
#   leaves none behind.
#   - No receipt, and the suite lock is held → a verify or land is running,
#     often this run's own, in the background. The turn ends with a note.
#   - No receipt, and the lock is free → the gate blocks with a reminder to
#     run verify. The reminder counts toward THE BLOCK CAP.
# The gate used to run --all here itself. In the hook's 600s it waited on the
# lock that the run's own background verify held, or the harness killed it,
# and a killed hook checks nothing. The receipt is not the merge check:
# `worktree.sh land` re-runs every check on the merge and publishes nothing
# on red. So a later commit that breaks the suite still reaches no trunk.
# (An adapter that expresses tier selection elsewhere, e.g. the Node template
# runs the project's own "test" script, treats --unit and --all alike.)
#
# Without the adapter the gate is a no-op, so it never gates a project that has
# not adopted hone. .hone-off disables it entirely. Type-check and lint are
# opt-in by their script existing. Tests are the minimum.
#
# Mechanism: a Stop hook may return {"decision":"block","reason":...} to keep
# the turn going, and the harness feeds the reason back to the model. When the
# turn may end it returns {"systemMessage":...} naming the checks that ran, or
# the record that let it run none. So the transcript records that the gate
# fired (silence would be indistinguishable from a skip).
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
# changes directory there first, so the suite, the receipt, and the memo all
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
            TIER="--all"; return 0 ;;       # committed on a change branch → the full tier
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
# msg_gate_step_failed. The full tier's reminder passes its own, so a run that
# never runs verify meets the same cap as a red check.
gate_block_or_cap() {
    local label="$1" rc="$2" tail="$3" first="${4:-}" file sig n=1 recorded msg
    file=$(gate_blocks_file)
    sig=$(gate_signature "$label" "$rc" "$tail")
    recorded=$(cat "$file" 2>/dev/null)
    case "$recorded" in
        "$SESSION $sig "*) n=$(( ${recorded##* } + 1 )) ;;
    esac
    # The reminder ran no suite, so its cap messages must not call it red.
    if [ "$n" -gt "$GATE_BLOCK_CAP" ]; then
        rm -f "$file" 2>/dev/null
        if [ "$rc" = unverified ]; then msg=$(msg_gate_verify_cap_reached "$n")
        else msg=$(msg_gate_cap_reached "$label" "$n"); fi
        printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$msg")"
        exit 0
    fi
    printf '%s %s %s\n' "$SESSION" "$sig" "$n" > "$file" 2>/dev/null || true
    if [ "$n" -eq "$GATE_BLOCK_CAP" ]; then
        [ "$rc" = unverified ] && block "$(msg_gate_verify_report_now "$n")"
        block "$(msg_gate_report_now "$label" "$n")"
    fi
    [ -n "$first" ] && block "$first"
    block "$(msg_gate_step_failed "$label" "$rc" "$tail")"
}

# A green turn ends the streak. The next red failure starts at one.
gate_clear_blocks() { rm -f "$(gate_blocks_file)" 2>/dev/null || true; }

# Exit 0 when a verify or a land holds the suite lock right now
# (<git-common-dir>/hone-land.lock, taken through hone_suite_lock). Two
# signs must agree: the lock is taken, and the queue's holder record names a
# live process (hone_queue_holder_live). A bare flock by anything else, such
# as a server that a suite left running or a lock taken by hand, is not a
# verify, so it does not let the turn end. The probe takes the lock for an
# instant on a read-only fd, so it never creates the file and never waits.
# Without flock, or without the file, the lock reads as free.
gate_suite_busy() {
    local lock
    command -v flock >/dev/null 2>&1 || return 1
    lock="$(git rev-parse --git-common-dir 2>/dev/null)/hone-land.lock"
    [ -r "$lock" ] || return 1
    { flock -n 8; } 8<"$lock" 2>/dev/null && return 1
    hone_queue_holder_live "$lock.queue"
}

# Exit 0 when a submodule holds uncommitted work: modified or untracked
# files inside it. `git add -A` records only a submodule's HEAD, so such an
# edit leaves hone_tree_state as it was. One status call, and none at all
# without .gitmodules.
gate_submodule_dirty() {
    [ -f .gitmodules ] || return 1
    git status --porcelain=v2 --ignore-submodules=none 2>/dev/null | awk '
        ($1 == "1" || $1 == "2") && substr($3, 1, 1) == "S" \
            && (substr($3, 3, 1) != "." || substr($3, 4, 1) != ".") { f = 1 }
        END { exit !f }'
}

GATE_TREE=""; VERIFIED_AT=""

# THE FULL TIER (see the header). The receipt's key is the version and the
# branch, and its tree decides whether a check runs. --git-dir resolves
# to .git/worktrees/<name> in a linked worktree, so each worktree keeps its
# own receipt. A line with another version or too few fields misses.
#
# An untracked input that git ignores (a dependency install) can change the
# result without changing the tree. The gate accepts that gap: land
# re-verifies on the merge.
if [ "$TIER" = "--all" ]; then
    read -r r_version r_branch r_tree r_by _ 2>/dev/null \
        <"$(git rev-parse --git-dir 2>/dev/null)/hone-gate-green"
    if [ "${r_by:-}" = verify ] && [ "$r_version" = "$(hone_plugin_version)" ] \
       && [ "$r_branch" = "$BRANCH" ]; then
        GATE_TREE=$(hone_tree_state)
        if [ -n "$GATE_TREE" ] && [ "$r_tree" = "$GATE_TREE" ]; then
            gate_clear_blocks
            printf '{"systemMessage":"%s"}\n' \
                "$(hone_json_escape "$(msg_gate_green_cached "$r_tree")")"
            exit 0
        fi
        # Commits since verify: the unit tier checks them below.
        TIER="--unit"; VERIFIED_AT="$r_tree"
    # A verify or land runs now, so its own result will follow. Blocking here
    # only made the run wait in empty turns on its own background job.
    elif gate_suite_busy; then
        printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$(msg_gate_verify_running)")"
        exit 0
    else
        gate_block_or_cap "verify" unverified "$BRANCH" "$(msg_gate_verify_missing)"
    fi
fi

# THE UNIT MEMO (see the header). Without git there is no tree to key on,
# and a submodule with uncommitted work hides it from the key. In both cases
# every step runs and no memo is written. A stale record goes before the run,
# so a red step leaves none.
GATE_MEMO=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    GATE_MEMO="$(git rev-parse --git-dir)/hone-gate-unit"
    [ -n "$GATE_TREE" ] || GATE_TREE=$(hone_tree_state)
    gate_submodule_dirty && GATE_TREE=""
fi
if [ -n "$GATE_TREE" ]; then
    if [ "$(cat "$GATE_MEMO" 2>/dev/null)" = "$(hone_plugin_version) $GATE_TREE" ]; then
        gate_clear_blocks
        printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$(msg_gate_green_memo "$GATE_TREE")")"
        exit 0
    fi
    rm -f "$GATE_MEMO" 2>/dev/null
fi

# Run an adapter, capturing a short tail of its output for the block reason.
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

run_step "tests ($TIER)" bash "$ADAPTER" "$TIER"
[ -f "scripts/typecheck.sh" ] && run_step "type-check" bash "scripts/typecheck.sh"
[ -f "scripts/lint.sh" ] && run_step "lint" bash "scripts/lint.sh"

# Every step went green. The tree measured before the run is the one they
# checked. A step that changed the tree moves it, so the next Stop runs again.
[ -n "$GATE_TREE" ] && printf '%s %s\n' "$(hone_plugin_version)" "$GATE_TREE" > "$GATE_MEMO" 2>/dev/null

# Every step went green, so no failure is repeating. The cap starts over.
gate_clear_blocks

# Green receipt: one visible line saying what actually ran, so a transcript can
# confirm the gate fired rather than inferring it from silence.
if [ -n "$VERIFIED_AT" ]; then
    printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$(msg_gate_green_since_verify "$VERIFIED_AT" "$ran")")"
else
    printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$(msg_gate_green "$ran")")"
fi
exit 0
