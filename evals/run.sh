#!/bin/bash
# Eval harness for hone's judgment prose: the two critic agents and the run
# skill's loop instructions. Prose is the one part of the trust foundation that
# can go stale silently (nothing type-checks a prompt), so this pins it to a
# suite of cases with known-good answers. It is also what makes *cutting* prose
# safe: trim the skill or a critic, re-run, and see whether the behaviour held.
#
# Three targets:
#   plan-critic, consolidate-critic: the critic agents. System prompt is the
#     agent body; the case is a constructed brief; the answer is its verdict.
#   loop: the run skill's own instructions. System prompt is skills/run/SKILL.md;
#     the case is a situation mid-run; the answer is the next action it picks.
#     These are the cases that say which paragraphs of the skill are load-bearing.
#
# Each case is a directory under evals/<target>/<case>/ with:
#   brief.md   is the case handed to the model (self-contained; no file reads
#                needed, mirroring the loop's constructed context)
#   expected   holds the expected token on line 1 (see tokens_for below). Any
#                further non-empty line is a substring the reply must mention
#                (e.g. a category like `collision`), checked case-insensitively.
#
# Every (case × vote) call is independent, so the calls fan out concurrently
# (throttled by --jobs) and scoring happens after they land.
#
# Usage:
#   bash evals/run.sh [plan-critic|consolidate-critic|loop|all] \
#                     [--model NAME] [--votes N] [--jobs N] [--dry-run]
#   --votes N   plurality vote over N runs per case (default 1); use 3 pre-release.
#   --jobs N    max concurrent model calls (default 8); raise for speed, but too
#               high can hit API concurrency limits and error a call.
#   --dry-run   list the cases and expected answers without calling the model.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

ALL_TARGETS=(plan-critic consolidate-critic loop)

WHICH="all"; MODEL="sonnet"; DRY=0; VOTES=1; JOBS=8
while [ $# -gt 0 ]; do
    case "$1" in
        plan-critic|consolidate-critic|loop|all) WHICH="$1" ;;
        --model) shift; MODEL="$1" ;;
        --votes) shift; VOTES="$1" ;;
        --jobs) shift; JOBS="$1" ;;
        --dry-run) DRY=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

# The tokens a target may answer with, MOST CONSERVATIVE FIRST: a tie in the
# vote breaks toward the earlier token, so a split critic rejects rather than
# approves, and a split loop stops rather than proceeds.
tokens_for() {
    case "$1" in
        plan-critic)        echo 'REJECT APPROVE' ;;
        consolidate-critic) echo 'CUTS CLEAN' ;;
        loop)               echo 'STOP SKIP DISCARD NEST RECORD BACKGROUND ASK EXPAND HANDROLL PROCEED' ;;
    esac
}

# Strip YAML frontmatter from a .md, leaving the prose body.
strip_fm() {
    awk 'BEGIN{fm=0} NR==1&&/^---[[:space:]]*$/{fm=1;next} fm&&/^---[[:space:]]*$/{fm=0;next} fm{next} {print}' "$1"
}

# The prose under test goes in the SYSTEM slot, exactly as the harness loads it.
sys_for() {
    case "$1" in
        loop) strip_fm "skills/run/SKILL.md" ;;
        *)    strip_fm "agents/$1.md" ;;
    esac
}

# The user turn. Only the closing instruction differs: a critic ends with its
# verdict, the loop ends with the action it would take next.
instruction_for() {
    case "$1" in
        loop) printf 'You are part-way through a hone run. Decide the single next action for the situation below, following your instructions exactly. State your reasoning briefly, then end with a final line of exactly:\nACTION: <TOKEN>\nwhere <TOKEN> is one of: %s\n' "$(tokens_for loop | tr ' ' ' ')" ;;
        *)    printf 'Review this case per your instructions. List your findings, then end with your one-line verdict.\n' ;;
    esac
}

should() { [ "$WHICH" = "all" ] || [ "$WHICH" = "$1" ]; }

TARGETS=()
for t in "${ALL_TARGETS[@]}"; do should "$t" && TARGETS+=("$t"); done

# --- Dry run: list cases and expected answers, no model calls. -----------------
if [ "$DRY" -eq 1 ]; then
    for target in "${TARGETS[@]}"; do
        echo "== $target =="
        for dir in evals/"$target"/*/; do
            [ -f "$dir/brief.md" ] || continue
            printf '  %-30s expect %-10s %s\n' "$(basename "$dir")" \
                "$(head -1 "$dir/expected" | tr -d '[:space:]')" \
                "$(tail -n +2 "$dir/expected" | tr '\n' ' ')"
        done
    done
    echo "-------------------------------------"
    echo "(dry run: no model calls)"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# One model call, writing its reply to a per-(target,case,vote) file. Runs in the
# background; failures degrade to an empty file (scored as no answer), never abort.
call_one() {
    local target="$1" dir="$2" name="$3" v="$4" sys user
    sys=$(sys_for "$target")
    user="$(instruction_for "$target")

$(cat "$dir/brief.md")"
    claude -p "$user" --append-system-prompt "$sys" --model "$MODEL" \
        > "$TMP/${target}~${name}~${v}.out" 2>/dev/null || true
}

# --- Phase 1: fan out every call, capped at $JOBS concurrent. -------------------
total_calls=0
running=0
for target in "${TARGETS[@]}"; do
    for dir in evals/"$target"/*/; do
        [ -f "$dir/brief.md" ] || continue
        name=$(basename "$dir")
        for v in $(seq 1 "$VOTES"); do
            call_one "$target" "$dir" "$name" "$v" &
            total_calls=$((total_calls+1))
            running=$((running+1))
            if [ "$running" -ge "$JOBS" ]; then wait -n; running=$((running-1)); fi
        done
    done
done
echo "running $total_calls model call(s) on $MODEL, up to $JOBS at a time..."
wait

# --- Phase 2: score from the collected outputs (deterministic order). ----------
score_target() {
    local target="$1" pass=0 fail=0
    echo "== $target =="
    local toks re
    toks=$(tokens_for "$target")
    re="\\b($(printf '%s' "$toks" | tr ' ' '|'))\\b"
    for dir in evals/"$target"/*/; do
        [ -f "$dir/brief.md" ] || continue
        local name expected; name=$(basename "$dir")
        expected=$(head -1 "$dir/expected" | tr -d '[:space:]')
        local -a required=(); while IFS= read -r l; do [ -n "$l" ] && required+=("$l"); done < <(tail -n +2 "$dir/expected")

        # Collect one vote per run: the last token mentioned, which the closing
        # verdict/ACTION line makes the model's actual answer rather than a token
        # it happened to name while reasoning.
        local allout="" out v
        local -a votes=()
        for v in $(seq 1 "$VOTES"); do
            out=$(cat "$TMP/${target}~${name}~${v}.out" 2>/dev/null)
            allout="$allout$out"
            votes+=("$(printf '%s\n' "$out" | grep -oE "$re" | tail -1)")
        done

        # No token from ANY vote means every call failed (network, rate limit, bad
        # --model) or returned garbage. That is an infrastructure failure, NOT a
        # pass. Fail loudly so a dead harness can't green a case by falling
        # through to whichever token happens to be the expected one.
        local answered=0 t
        for t in "${votes[@]}"; do [ -n "$t" ] && answered=$((answered+1)); done
        if [ "$answered" -eq 0 ]; then
            printf '  FAIL  %-30s → no answer from %s call(s); model/API failure?\n' "$name" "$VOTES"
            fail=$((fail+1)); continue
        fi

        # Plurality. Strict > keeps the FIRST token at the max count, so ties break
        # toward the more conservative token (tokens_for orders them that way).
        local verdict="" best=0 n
        for t in $toks; do
            n=0
            local vt; for vt in "${votes[@]}"; do [ "$vt" = "$t" ] && n=$((n+1)); done
            if [ "$n" -gt "$best" ]; then best="$n"; verdict="$t"; fi
        done

        local missing=""
        for r in "${required[@]}"; do printf '%s' "$allout" | grep -qiF "$r" || missing="$missing $r"; done

        if [ "$verdict" = "$expected" ] && [ -z "$missing" ]; then
            printf '  ok    %-30s → %s\n' "$name" "$verdict"; pass=$((pass+1))
        else
            printf '  FAIL  %-30s → got "%s" want "%s"%s\n' "$name" "$verdict" "$expected" \
                "${missing:+ (missing:$missing)}"; fail=$((fail+1))
        fi
    done
    echo "  $target: $pass pass, $fail fail"
    return "$fail"
}

total_fail=0
for target in "${TARGETS[@]}"; do
    score_target "$target" || total_fail=$((total_fail+$?))
done

echo "-------------------------------------"
echo "total failures: $total_fail"
[ "$total_fail" -eq 0 ]
