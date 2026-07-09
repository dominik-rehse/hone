#!/bin/bash
# Eval harness for hone's judgment prose — the two critic agents and, by
# extension, the behaviour-shaping rule. The critics and the injected rule are
# the one part of the trust foundation that can rot silently (unverified prose),
# so this pins them to a suite of cases with known-good verdicts.
#
# Each case is a directory under evals/<critic>/<case>/ with:
#   brief.md   — the constructed brief handed to the critic (self-contained;
#                no file reads needed, mirroring the loop's constructed context)
#   expected   — line 1: the expected verdict token (ADMIT|REJECT for
#                plan-critic; CLEAN|CUTS for consolidate-critic). Any further
#                non-empty lines are substrings the critic's findings must
#                mention (e.g. a category like `collision`), each checked.
#
# The harness runs each critic faithfully: its agent body (frontmatter stripped)
# goes in the SYSTEM slot, the brief is the user turn, and it shells out to a
# headless `claude -p`. Every (case × vote) call is independent, so the calls fan
# out concurrently (throttled by --jobs) and scoring happens after they land.
#
# Usage:
#   bash evals/run.sh [plan-critic|consolidate-critic|all] \
#                     [--model NAME] [--votes N] [--jobs N] [--dry-run]
#   --votes N   majority vote over N runs per case (default 1); use 3 pre-release.
#   --jobs N    max concurrent model calls (default 8); raise for speed, but too
#               high can hit API concurrency limits and error a call.
#   --dry-run   list the cases and expected verdicts without calling the model.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

WHICH="all"; MODEL="sonnet"; DRY=0; VOTES=1; JOBS=8
while [ $# -gt 0 ]; do
    case "$1" in
        plan-critic|consolidate-critic|all) WHICH="$1" ;;
        --model) shift; MODEL="$1" ;;
        --votes) shift; VOTES="$1" ;;
        --jobs) shift; JOBS="$1" ;;
        --dry-run) DRY=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

# The verdict tokens a critic may emit; field 1 is "clean/admit", field 2 "flagged".
verdict_re() { case "$1" in plan-critic) echo 'ADMIT|REJECT';; consolidate-critic) echo 'CLEAN|CUTS';; esac; }

# Strip YAML frontmatter from an agent .md, leaving the system prompt body.
strip_fm() {
    awk 'BEGIN{fm=0} NR==1&&/^---[[:space:]]*$/{fm=1;next} fm&&/^---[[:space:]]*$/{fm=0;next} fm{next} {print}' "$1"
}

should() { [ "$WHICH" = "all" ] || [ "$WHICH" = "$1" ]; }

CRITICS=()
should plan-critic && CRITICS+=(plan-critic)
should consolidate-critic && CRITICS+=(consolidate-critic)

# --- Dry run: list cases and expected verdicts, no model calls. ----------------
if [ "$DRY" -eq 1 ]; then
    for critic in "${CRITICS[@]}"; do
        echo "== $critic =="
        for dir in evals/"$critic"/*/; do
            [ -f "$dir/brief.md" ] || continue
            printf '  %-28s expect %s %s\n' "$(basename "$dir")" \
                "$(head -1 "$dir/expected" | tr -d '[:space:]')" \
                "$(tail -n +2 "$dir/expected" | tr '\n' ' ')"
        done
    done
    echo "-------------------------------------"
    echo "(dry run — no model calls)"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# One model call, writing its reply to a per-(critic,case,vote) file. Runs in the
# background; failures degrade to an empty file (scored as no verdict), never abort.
call_one() {
    local critic="$1" dir="$2" name="$3" v="$4" sys user
    sys=$(strip_fm "agents/$critic.md")
    user="Review this case per your instructions. List your findings, then end with your one-line verdict.

$(cat "$dir/brief.md")"
    claude -p "$user" --append-system-prompt "$sys" --model "$MODEL" \
        > "$TMP/${critic}~${name}~${v}.out" 2>/dev/null || true
}

# --- Phase 1: fan out every call, capped at $JOBS concurrent. -------------------
total_calls=0
running=0
for critic in "${CRITICS[@]}"; do
    for dir in evals/"$critic"/*/; do
        [ -f "$dir/brief.md" ] || continue
        name=$(basename "$dir")
        for v in $(seq 1 "$VOTES"); do
            call_one "$critic" "$dir" "$name" "$v" &
            total_calls=$((total_calls+1))
            running=$((running+1))
            if [ "$running" -ge "$JOBS" ]; then wait -n; running=$((running-1)); fi
        done
    done
done
echo "running $total_calls model call(s), up to $JOBS at a time..."
wait

# --- Phase 2: score from the collected outputs (deterministic order). ----------
score_critic() {
    local critic="$1" pass=0 fail=0
    echo "== $critic =="
    local re flagged clean
    re=$(verdict_re "$critic"); flagged=$(printf '%s' "$re" | cut -d'|' -f2); clean=$(printf '%s' "$re" | cut -d'|' -f1)
    for dir in evals/"$critic"/*/; do
        [ -f "$dir/brief.md" ] || continue
        local name expected_verdict; name=$(basename "$dir")
        expected_verdict=$(head -1 "$dir/expected" | tr -d '[:space:]')
        local -a required=(); while IFS= read -r l; do [ -n "$l" ] && required+=("$l"); done < <(tail -n +2 "$dir/expected")

        local allout="" out vote c_flag=0 c_clean=0 v
        for v in $(seq 1 "$VOTES"); do
            out=$(cat "$TMP/${critic}~${name}~${v}.out" 2>/dev/null)
            allout="$allout$out"
            vote=$(printf '%s\n' "$out" | grep -oE "$re" | tail -1)
            if [ "$vote" = "$flagged" ]; then c_flag=$((c_flag+1)); elif [ -n "$vote" ]; then c_clean=$((c_clean+1)); fi
        done
        # No verdict token from ANY vote means every call failed (network, rate
        # limit, bad --model) or returned garbage. That is an infrastructure
        # failure, NOT a clean pass — fail loudly so a dead harness can't green a
        # clean-expected case by falling through to the clean verdict.
        if [ $((c_flag + c_clean)) -eq 0 ]; then
            printf '  FAIL  %-28s → no verdict from %s call(s) — model/API failure?\n' "$name" "$VOTES"
            fail=$((fail+1)); continue
        fi

        # Majority; ties break toward the flagged token (the conservative call).
        local verdict
        if [ "$c_flag" -ge "$c_clean" ] && [ "$c_flag" -gt 0 ]; then verdict="$flagged"; else verdict="$clean"; fi

        local missing=""
        for r in "${required[@]}"; do printf '%s' "$allout" | grep -qiF "$r" || missing="$missing $r"; done

        if [ "$verdict" = "$expected_verdict" ] && [ -z "$missing" ]; then
            printf '  ok    %-28s → %s\n' "$name" "$verdict"; pass=$((pass+1))
        else
            printf '  FAIL  %-28s → got "%s" want "%s"%s\n' "$name" "$verdict" "$expected_verdict" \
                "${missing:+ (missing:$missing)}"; fail=$((fail+1))
        fi
    done
    echo "  $critic: $pass pass, $fail fail"
    return "$fail"
}

total_fail=0
for critic in "${CRITICS[@]}"; do
    score_critic "$critic" || total_fail=$((total_fail+$?))
done

echo "-------------------------------------"
echo "total failures: $total_fail"
[ "$total_fail" -eq 0 ]
