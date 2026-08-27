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
#     under the land lock, after the merge: that one gates the trunk and rolls
#     back on red. Keep the suite within the hook timeout to keep this backstop
#     meaningful.
#   - Clean tree on any other branch → nothing in flight, no-op.
#   - No git → the unit tier (the gate cannot tell what is in flight, and
#     adapter presence already scopes this to hone projects).
#
# The --ALL tier runs once per change BRANCH, not once per commit. A green run
# records the branch, and every later Stop on that branch skips the suite. The
# backstop's value is one early warning per change. It tells the model that this
# change breaks an integration test, while the change is still open. A re-run
# after each new commit re-verifies almost the same code, and it adds little.
# The repeats also cost the most. They hold the land lock, so they collide with
# each other and with lands. `worktree.sh land` re-runs --all after the merge
# and rolls back on red. So a regression that a later commit introduces still
# never reaches the trunk.
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

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/messages.sh"

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

# Pick the tier by where the work sits (see the header). A bare Q&A turn on a
# clean, non-change tree has nothing to verify and exits early.
TIER="--unit"
BRANCH=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "$(gate_durable_dirt)" ]; then
        TIER="--unit"                       # red-green in flight → fast tier
    else
        BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        case "$BRANCH" in
            hone/*) TIER="--all" ;;         # committed on a change branch → full pre-land check
            *) exit 0 ;;                    # clean, not a change branch → nothing to verify
        esac
    fi
fi

# $1 = a template from messages.sh (already prefixed).
block() { hone_stop_block "$1"; exit 0; }

# The green receipt for the full tier: one line,
# "<plugin version> <branch> <tree hash>", in <git-dir>/hone-gate-green. The
# SKIP key is the first two fields. The tree records what the run verified, and
# the skip never compares it. --git-dir resolves to .git/worktrees/<name> in a
# linked worktree, so each worktree keeps its own receipt. The version prefix
# makes a plugin upgrade a miss: a gate with new steps must not trust a receipt
# an older gate wrote. A receipt that an older gate wrote carries no branch
# field, so it misses too, and the suite runs one more time.
#
# An untracked input (a dependency install, a stale node_modules) can change the
# result without changing the branch. The gate accepts that gap, the
# same way it accepts the 600s hook timeout: land re-verifies authoritatively.
#
# The unit tier stays unmemoized. It runs on a dirty tree, whose state no commit
# names, and it is cheap by design.
GATE_RECEIPT=""
GATE_KEY=""     # "<version> <branch>", the skip key
GATE_LINE=""    # what a green run writes: the skip key plus the verified tree
gate_receipt_key() {
    local tree version
    tree=$(git rev-parse 'HEAD^{tree}' 2>/dev/null) || return 1
    [ -n "$tree" ] || return 1
    [ -n "$BRANCH" ] || return 1
    version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$(dirname -- "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json" 2>/dev/null | head -1)
    GATE_RECEIPT="$(git rev-parse --git-dir 2>/dev/null)/hone-gate-green"
    GATE_KEY="${version:-unknown} $BRANCH"
    GATE_LINE="$GATE_KEY $tree"
}

# Skip a repeat of the full tier BEFORE the lock block below, so a skip removes
# contention instead of queueing on it. The skip still prints a receipt: silence
# is indistinguishable from a gate that never fired.
if [ "$TIER" = "--all" ] && gate_receipt_key; then
    recorded=$(cat "$GATE_RECEIPT" 2>/dev/null)
    # Drop the trailing tree field and compare the rest. A git branch name never
    # holds a space, so the remainder is exactly "<version> <branch>". A
    # two-field line from an older gate leaves the version alone, which misses.
    if [ -n "$recorded" ] && [ "${recorded% *}" = "$GATE_KEY" ]; then
        printf '{"systemMessage":"%s"}\n' \
            "$(hone_json_escape "$(msg_gate_green_cached "${recorded##* }")")"
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
        tail=$(printf '%s\n' "$out" | tail -n 15)
        block "$(msg_gate_step_failed "$label" "$rc" "$tail")"
    fi
    ran+="${ran:+, }$label"
}

# The full tier shares land's lock (<git-common-dir>/hone-land.lock). e2e tiers
# are load-sensitive, so a --all racing another session's suite or a land's
# re-verify poisons both signals (phantom flakes, spurious land rollbacks).
# Short wait only: if a suite is live, blocking the stop with "retry" beats
# running red under contention. The unit tier stays lock-free: it is the
# per-Stop inner loop and must stay cheap. Without flock, degrade to running
# unserialized rather than not at all.
if [ "$TIER" = "--all" ] && command -v flock >/dev/null 2>&1; then
    SUITE_LOCK="$(git rev-parse --git-common-dir 2>/dev/null)/hone-land.lock"
    if { exec 9>"$SUITE_LOCK"; } 2>/dev/null; then
        flock -w "${HONE_SUITE_LOCK_TIMEOUT:-30}" 9 || \
            block "$(msg_gate_suite_lock)"
    fi
fi

run_step "tests ($TIER)" bash "$ADAPTER" "$TIER"
[ -f "scripts/typecheck.sh" ] && run_step "type-check" bash "scripts/typecheck.sh"
[ -f "scripts/lint.sh" ] && run_step "lint" bash "scripts/lint.sh"

# Record the branch and the verified tree, so every later Stop on this branch
# skips the suite. Only after every step went green, and only for the full tier.
if [ "$TIER" = "--all" ] && [ -n "$GATE_LINE" ]; then
    printf '%s\n' "$GATE_LINE" > "$GATE_RECEIPT" 2>/dev/null || true
fi

# Green receipt: one visible line saying what actually ran, so a transcript can
# confirm the gate fired rather than inferring it from silence.
printf '{"systemMessage":"%s"}\n' "$(hone_json_escape "$(msg_gate_green "$ran")")"
exit 0
