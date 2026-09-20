#!/bin/bash
# Tier 2: the decision-point suite. It resumes a recorded `/hone:run` session
# just before a decision and grades the next action, through
# `claude plugin eval` and `context.history_file`.
#
# A case costs cents, where a lab run costs dollars
# (`docs/spikes/2026-09-20-decision-point-cases.md`). Step 8 of HANDOFF.md
# uses this script as its evaluator, so it takes the plugin under test as an
# argument: a candidate is a copy of the plugin with another
# `skills/run/SKILL.md`.
#
# Usage:
#   bash evals/decision-points/run.sh [options]
#     --plugin DIR   the plugin under test (default: this repository)
#     --model ID     the model of the resumed session (default: claude-opus-5)
#     --runs N       runs per case (default: 3)
#     --case GLOB    only the cases whose name matches (one glob, no braces)
#     --tag T        only the cases with this tag; repeatable. Every case is
#                    tagged with its step of the loop and with its scenario
#     --json FILE    where the runner's own result goes
#     --work DIR     the sandbox (default: /var/tmp/hone-dp/<timestamp>)
#     --keep-temp    keep each run's workspace, for reading a failure
#     --dry-run      print the command and the conditions, call no model
#   Anything after `--` goes to `claude plugin eval` unchanged.
#
# It prints one JSON line per case: case, pass, runs, passed, cost, seconds.
#
# THREE CONDITIONS OF THIS MACHINE, from the spike of 2026-09-20. Each one
# refuses a run before any model call, so this script checks all three and
# says what to do.
#   1. A clean HOME. The Bash sandbox refuses to start when `~/.docker` holds
#      a symbolic link, which Docker Desktop on WSL2 puts there.
#   2. A session token in the environment, because the clean HOME holds no
#      credentials. It comes from evals/session-token.sh and is never stored.
#   3. `socat` on PATH, beside `bwrap`. Set HONE_DP_SOCAT_DIR when the machine
#      has no socat package.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1  # no bytecode cache in the repository
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

PLUGIN="$ROOT"
MODEL=claude-opus-5
RUNS=3
CASE='*'
TAGS=()
JSON=""
WORK=""
KEEP=""
DRY=""
EXTRA=()
while [ $# -gt 0 ]; do
    case "$1" in
        --plugin) PLUGIN=$(cd "$2" && pwd) || exit 2; shift 2;;
        --model) MODEL="$2"; shift 2;;
        --runs) RUNS="$2"; shift 2;;
        --case) CASE="$2"; shift 2;;
        --tag) TAGS+=("$2"); shift 2;;
        --json) JSON="$2"; shift 2;;
        --work) WORK="$2"; shift 2;;
        --keep-temp) KEEP=--keep-temp; shift;;
        --dry-run) DRY=1; shift;;
        --) shift; EXTRA=("$@"); break;;
        *) echo "run.sh: unknown option $1" >&2; exit 2;;
    esac
done
WORK="${WORK:-/var/tmp/hone-dp/$(date +%Y%m%d-%H%M%S)}"
JSON="${JSON:-$WORK/result.json}"

die() { echo "decision-points: $*" >&2; exit 2; }

REAL_CLAUDE=$(command -v claude) || die "no claude on PATH"
command -v jq >/dev/null || die "no jq on PATH"
command -v python3 >/dev/null || die "no python3 on PATH"
command -v bwrap >/dev/null || die "no bwrap on PATH. The Bash sandbox of the
runner needs it. Install bubblewrap."

# Condition 3: socat.
SOCAT_DIR="${HONE_DP_SOCAT_DIR:-}"
if ! command -v socat >/dev/null; then
    [ -n "$SOCAT_DIR" ] && [ -x "$SOCAT_DIR/socat" ] || die "no socat on PATH.
The Bash sandbox of the runner needs it beside bwrap. Install the socat
package, or unpack it somewhere and set HONE_DP_SOCAT_DIR to the directory
that holds the binary."
    PATH="$SOCAT_DIR:$PATH"
    export PATH
fi

# Condition 2: the token. Never written to disk, and never into this repo.
CREDENTIALS="$HOME/.claude/.credentials.json"
export CREDENTIALS REAL_CLAUDE
TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    # shellcheck source=../session-token.sh
    . "$ROOT/evals/session-token.sh"
    refresh_session_token || die "no usable session token. Log in again, or
set CLAUDE_CODE_OAUTH_TOKEN."
    TOKEN=$(session_token)
fi

[ -d "$PLUGIN/skills/run" ] || die "$PLUGIN is no hone plugin: no skills/run/"

# Condition 1: a clean HOME, and a plugin copy small enough for the runner
# (it refuses a directory of more than 20,000 entries, and this repository
# holds about 40,000 with evals/lab/out/ in it).
mkdir -p "$WORK/home" "$WORK/docker" "$WORK/plugin/dp" || die "cannot write $WORK"
for d in .claude-plugin agents hooks rules scripts skills templates; do
    cp -r "$PLUGIN/$d" "$WORK/plugin/" || die "cannot copy $PLUGIN/$d"
done
cp -r "$HERE/lib" "$HERE/fixtures" "$HERE/cases" "$WORK/plugin/dp/" || die "cannot copy the suite"

CMD=("$REAL_CLAUDE" plugin eval . --eval-dir dp --case "$CASE"
     --runs "$RUNS" --ablation none --model "$MODEL" -j 1
     --trust-plugin --scaffold --allow-tools Bash Write Edit
     --no-publish --json "$JSON")
[ -n "$KEEP" ] && CMD+=("$KEEP")
for t in ${TAGS[@]+"${TAGS[@]}"}; do CMD+=(--tag "$t"); done
[ "${#EXTRA[@]}" -gt 0 ] && CMD+=("${EXTRA[@]}")

CASES=$(find "$HERE/cases" -maxdepth 1 -mindepth 1 -type d | wc -l)
# A run measured 50 cents on claude-opus-5 and 20 cents on claude-sonnet-5
# on 2026-09-20, with a turn cap of 3.
case "$MODEL" in *sonnet*|*haiku*) CENTS=20;; *) CENTS=50;; esac
printf 'decision-points: %s case(s) x %s run(s) on %s, about $%s of plan usage\n' \
    "$CASES" "$RUNS" "$MODEL" "$(( CASES * RUNS * CENTS / 100 ))" >&2
if [ -n "$DRY" ]; then
    printf 'work   %s\nplugin %s\nsocat  %s\ncmd    %s\n' \
        "$WORK" "$PLUGIN" "$(command -v socat)" "${CMD[*]}" >&2
    exit 0
fi

HOME="$WORK/home" DOCKER_CONFIG="$WORK/docker" \
    CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
    bash -c 'cd "$1" && shift && exec "$@"' _ "$WORK/plugin" "${CMD[@]}" >&2
rc=$?

[ -f "$JSON" ] || die "the runner wrote no $JSON (exit $rc)"
jq -c '.cases[] | {
    case: .name,
    pass: (.aggregates.passRate == 1),
    runs: (.arms.with | length),
    passed: ([.arms.with[] | select(.passed)] | length),
    cost: ([.arms."with"[].costUsd] | add),
    seconds: ([.arms."with"[].durationSeconds] | add)
}' "$JSON"
echo "decision-points: $JSON" >&2
exit "$rc"
