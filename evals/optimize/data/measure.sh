#!/bin/bash
# Run a critic prompt over cases that live outside this repository.
#
# `evals/run.sh` reads its cases from `evals/<target>/<case>/` and has no flag
# for a case directory elsewhere. Training data must not enter the repository,
# so this script repeats run.sh's call shape instead: the prose under test in
# the system slot, the same closing instruction, an empty working directory,
# --safe-mode, and every file tool denied. Read `call_one` in run.sh for why
# each of those is there.
#
# A case directory holds `brief.md` and `expected`, exactly as run.sh has it.
# The first line of `expected` is the token.
#
# Usage:
#   bash evals/optimize/data/measure.sh --cases-dir DIR --out FILE [options]
#     --ids FILE        one case name per line. Default: every directory.
#     --model NAME      default: the model in the agent's frontmatter.
#     --prompt-file F   prose under test, in place of agents/plan-critic.md.
#     --preface FILE    text prepended to every user turn, before the brief.
#     --votes N         votes per case, scored by plurality (default 1).
#     --jobs N          concurrent calls (default 8).
#     --agent NAME      the agent whose body and instruction to use
#                       (default plan-critic).
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CASES=""; OUT=""; IDS=""; MODEL=""; PROMPT_FILE=""; PREFACE=""
VOTES=1; JOBS=8; AGENT=plan-critic

while [ $# -gt 0 ]; do
    case "$1" in
        --cases-dir) shift; CASES="$1" ;;
        --out) shift; OUT="$1" ;;
        --ids) shift; IDS="$1" ;;
        --model) shift; MODEL="$1" ;;
        --prompt-file) shift; PROMPT_FILE="$1" ;;
        --preface) shift; PREFACE="$1" ;;
        --votes) shift; VOTES="$1" ;;
        --jobs) shift; JOBS="$1" ;;
        --agent) shift; AGENT="$1" ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$CASES" ] && [ -n "$OUT" ] || { echo "need --cases-dir and --out" >&2; exit 2; }

strip_fm() {
    awk 'BEGIN{fm=0} NR==1&&/^---[[:space:]]*$/{fm=1;next} fm&&/^---[[:space:]]*$/{fm=0;next} fm{next} {print}' "$1"
}

if [ -n "$MODEL" ]; then
    MODEL_ID="$MODEL"
else
    MODEL_ID=$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^model:/{print $2}' "$ROOT/agents/$AGENT.md")
fi
SYS=$(strip_fm "${PROMPT_FILE:-$ROOT/agents/$AGENT.md}")
INSTRUCTION='Review this case per your instructions. List your findings, then end with a final line of exactly:
VERDICT: <TOKEN>
where <TOKEN> is APPROVE or REJECT.'
[ -n "$PREFACE" ] && INSTRUCTION="$INSTRUCTION

$(cat "$PREFACE")"
NO_TOOLS="Read Grep Glob Bash Task Agent Edit Write NotebookEdit WebFetch WebSearch"

if [ -n "$IDS" ]; then
    mapfile -t NAMES < <(grep -v '^[[:space:]]*$' "$IDS")
else
    mapfile -t NAMES < <(cd "$CASES" && for d in */; do [ -f "$d/brief.md" ] && echo "${d%/}"; done)
fi
[ "${#NAMES[@]}" -gt 0 ] || { echo "no cases in $CASES" >&2; exit 2; }

CALLS=$(( ${#NAMES[@]} * VOTES ))
printf 'model: %s\n' "$MODEL_ID"
printf 'prose: %s\n' "${PROMPT_FILE:-agents/$AGENT.md}"
printf 'cases: %d, votes: %d, calls: %d\n' "${#NAMES[@]}" "$VOTES" "$CALLS"
# 30 cents is the measured cost of one plan-critic call on a real field brief,
# on claude-opus-5, on 2026-09-20. A field brief is about 1,400 words and opus
# writes a long finding list before the verdict. A unit case in evals/run.sh is
# shorter and costs about 2 cents.
printf 'estimate: about %.2f dollars of plan usage at 30 cents per call\n' \
    "$(echo "$CALLS" | awk '{print $1*0.30}')"

TMP=$(mktemp -d)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$TMP" "$SANDBOX"' EXIT

call_one() {
    local name="$1" vote="$2" user
    user="$INSTRUCTION

$(cat "$CASES/$name/brief.md")"
    (cd "$SANDBOX" && claude -p "$user" --append-system-prompt "$SYS" \
        --model "$MODEL_ID" --safe-mode --disallowedTools "$NO_TOOLS" \
        --output-format json) > "$TMP/$name~$vote.json" 2>/dev/null || true
}

running=0
for name in "${NAMES[@]}"; do
    for vote in $(seq 1 "$VOTES"); do
        call_one "$name" "$vote" &
        running=$((running + 1))
        [ "$running" -ge "$JOBS" ] && { wait -n 2>/dev/null || true; running=$((running - 1)); }
    done
done
wait

python3 - "$TMP" "$CASES" "$OUT" "$MODEL_ID" <<'PY'
import collections, json, os, pathlib, re, sys

tmp, cases, out, model = sys.argv[1:5]
votes = collections.defaultdict(list)
cost = 0.0

for fname in sorted(os.listdir(tmp)):
    name, _, vote = fname[:-5].rpartition("~")
    env = {}
    try:
        env = json.loads(pathlib.Path(tmp, fname).read_text())
    except Exception:
        pass
    reply = "" if env.get("is_error", True) else (env.get("result") or "")
    cost += env.get("total_cost_usd") or 0.0
    hits = re.findall(r"\b(APPROVE|REJECT)\b", reply.upper())
    votes[name].append({"vote": int(vote), "token": hits[-1] if hits else "",
                        "cost_usd": env.get("total_cost_usd") or 0.0,
                        "reply": reply})

tally = collections.defaultdict(lambda: [0, 0, 0])   # right, wrong, no answer
records = []
for name, casts in sorted(votes.items()):
    expected = pathlib.Path(cases, name, "expected").read_text().strip().splitlines()[0]
    counted = collections.Counter(c["token"] for c in casts if c["token"])
    # A tie breaks toward the conservative token, as run.sh does.
    verdict = ""
    if counted:
        top = max(counted.values())
        for token in ("REJECT", "APPROVE"):
            if counted.get(token, 0) == top:
                verdict = token
                break
    slot = 2 if not verdict else (0 if verdict == expected else 1)
    tally[expected][slot] += 1
    records.append({"case": name, "expected": expected, "verdict": verdict,
                    "model": model, "pass": verdict == expected,
                    "tally": dict(counted), "votes": casts})

with open(out, "w") as fh:
    for r in records:
        fh.write(json.dumps(r) + "\n")

print()
for label in ("REJECT", "APPROVE"):
    right, wrong, dead = tally[label]
    total = right + wrong + dead
    if not total:
        continue
    pct = 100.0 * right / total
    print(f"{label:8}: {right}/{total} right, {wrong} wrong, {dead} no answer  [{pct:.0f}%]")
print(f"\ncost: {cost:.2f} dollars")
print(f"replies: {out}")
PY
