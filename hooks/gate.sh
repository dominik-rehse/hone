#!/bin/bash
# Stop-hook gate (Claude Code). The mechanical verify law: the durable suite must
# be green. Runs the project's one test adapter (scripts/run-tests.sh) and, where
# the language has them, the optional type-check and lint adapters
# (scripts/typecheck.sh, scripts/lint.sh). Any failure BLOCKS the stop so the
# model fixes it before finishing the turn — it never disables a gate to proceed.
#
# Which tier runs depends on where the work sits:
#   - Uncommitted src/tests changes → the fast UNIT tier. This is the red-green
#     inner loop; the gate must stay cheap on every turn or it gets disabled.
#   - Clean tree on a hone/<change> worktree branch (work committed, about to
#     land) → the full --ALL tier, including integration/e2e. This is the moment a
#     change is about to merge, so an integration regression that a green unit
#     tier would miss is caught mechanically here rather than trusting the run
#     skill's prose --all step.
#   - Clean tree on any other branch → nothing in flight, no-op.
#   - No git → the unit tier (can't tell what's in flight; adapter presence
#     already scopes this to hone projects).
# (Adapters that express tier selection elsewhere — e.g. the Node template runs
# the project's own "test" script — treat --unit and --all alike; the escalation
# only bites where the adapter distinguishes tiers.)
#
# Absent the adapter the gate is a no-op, so a project that has not adopted hone
# is never gated. Disabled entirely by .hone-off. Type-check/lint are opt-in by
# their script existing; tests are the floor.
#
# Mechanism: a Stop hook may return {"decision":"block","reason":...} to keep the
# turn going with the reason fed back to the model. On green it returns
# {"systemMessage":...} naming the checks that ran, so the transcript records
# that the gate fired (silence would be indistinguishable from a skip).

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0

[ -f ".hone-off" ] && exit 0

ADAPTER="scripts/run-tests.sh"
[ -f "$ADAPTER" ] || exit 0   # project has no hone test adapter — not gated

# Pick the tier by where the work sits (see the header). A bare Q&A turn on a
# clean, non-change tree has nothing to verify and exits early.
TIER="--unit"
if git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain -- src tests 2>/dev/null)" ]; then
        TIER="--unit"                       # red-green in flight → fast tier
    else
        case "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" in
            hone/*) TIER="--all" ;;         # committed on a change branch → full pre-land check
            *) exit 0 ;;                    # clean, not a change branch → nothing to verify
        esac
    fi
fi

block() { hone_stop_block "hone gate: $*"; exit 0; }

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
        block "$label failed (exit $rc). Fix it before finishing — do not disable the gate. Output tail:"$'\n'"${tail}"
    fi
    ran+="${ran:+, }$label"
}

# The full tier shares land's lock (<git-common-dir>/hone-land.lock): e2e tiers
# are load-sensitive, so a --all racing another session's suite or a land's
# re-verify poisons both signals (phantom flakes, spurious land rollbacks).
# Short wait only — if a suite is live, blocking the stop with "retry" beats
# running red under contention. The unit tier stays lock-free: it is the
# per-Stop inner loop and must stay cheap. Without flock, degrade to running
# unserialized rather than not at all.
if [ "$TIER" = "--all" ] && command -v flock >/dev/null 2>&1; then
    SUITE_LOCK="$(git rev-parse --git-common-dir 2>/dev/null)/hone-land.lock"
    if { exec 9>"$SUITE_LOCK"; } 2>/dev/null; then
        flock -w "${HONE_SUITE_LOCK_TIMEOUT:-30}" 9 || \
            block "another session is running the full suite (a land or verify holds the suite lock) — wait and re-verify rather than racing it; do not run the suite concurrently."
    fi
fi

run_step "tests ($TIER)" bash "$ADAPTER" "$TIER"
[ -f "scripts/typecheck.sh" ] && run_step "type-check" bash "scripts/typecheck.sh"
[ -f "scripts/lint.sh" ] && run_step "lint" bash "scripts/lint.sh"

# Green receipt: one visible line saying what actually ran, so a transcript can
# confirm the gate fired rather than inferring it from silence.
printf '{"systemMessage":"hone gate: green (%s)"}\n' "$(hone_json_escape "$ran")"
exit 0
