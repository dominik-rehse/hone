#!/bin/bash
# Does a bullet's generated cases aim at that bullet?
#
# For each bullet under *What to hunt* in `agents/plan-critic.md`, this runs
# the bullet's cases twice: on the full prompt, and on the prompt with that
# bullet cut. A case that flips is a case the bullet carries. A case that
# holds either needs no bullet on this model, or is too easy.
#
# The cut takes the bullet's category word out of the *Output* list too. The
# ablation of 2026-09-18 found that the word alone carries the bullet on
# opus (`docs/spikes/2026-09-18-section-ablation-on-opus.md`).
#
# The full-prompt half is also the seed measurement of the generated part,
# so nothing is run twice.
#
# Usage: bash evals/optimize/data/discriminate.sh <set_dir> <out_dir> [--model M]
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SET=${1:?need the set dir}
OUT=${2:?need an out dir}
shift 2
MODEL_ARG=("$@")

PROMPT="$ROOT/agents/plan-critic.md"
SECTIONS="$ROOT/evals/optimize/sections.py"
mkdir -p "$OUT"
export PYTHONDONTWRITEBYTECODE=1

# bullet unit name : the category word it owns in the Output list
BULLETS=(
    "placeholders:placeholder"
    "contradictions:contradiction"
    "ambiguity:ambiguity"
    "missing-baseline:missing-baseline"
    "scope:scope"
    "prose-doing-an-artifacts-job:missing-artifact"
    "dependency-and-toolchain-refreshes:"
    "collision-with-an-open-change:collision"
    "slug-collision:slug-collision"
    "contract-churn:contract-churn"
)

# Every generated case, full prompt. This is the seed of the generated part.
python3 - "$SET" > "$OUT/generated.ids" <<'PY'
import json, sys
items = json.load(open(sys.argv[1] + "/index.json"))["items"]
for i in items:
    if i["origin"] == "generated":
        print(i["id"])
PY
echo "=== full prompt, every generated case"
bash "$ROOT/evals/optimize/data/measure.sh" --cases-dir "$SET/cases" \
    --ids "$OUT/generated.ids" --out "$OUT/full.jsonl" --jobs 12 "${MODEL_ARG[@]}"

for entry in "${BULLETS[@]}"; do
    name=${entry%%:*}
    word=${entry#*:}
    python3 - "$SET" "$name" > "$OUT/$name.ids" <<'PY'
import json, sys
items = json.load(open(sys.argv[1] + "/index.json"))["items"]
for i in items:
    if i.get("category") == sys.argv[2]:
        print(i["id"])
PY
    [ -s "$OUT/$name.ids" ] || { echo "no cases for $name"; continue; }
    variant="$OUT/minus-$name.md"
    python3 "$SECTIONS" drop "$PROMPT" -s "what-to-hunt/$name" --fine -o "$variant"
    if [ -n "$word" ]; then
        python3 - "$variant" "$word" <<'PY'
import re, sys
path, word = sys.argv[1], sys.argv[2]
text = open(path).read()
# The Output list names each category in backticks, separated by pipes.
text = re.sub(r"`%s`\s*\|\s*" % re.escape(word), "", text)
text = re.sub(r"\|\s*`%s`" % re.escape(word), "", text)
open(path, "w").write(text)
PY
    fi
    echo "=== minus $name"
    bash "$ROOT/evals/optimize/data/measure.sh" --cases-dir "$SET/cases" \
        --ids "$OUT/$name.ids" --out "$OUT/minus-$name.jsonl" \
        --prompt-file "$variant" --jobs 12 "${MODEL_ARG[@]}"
done

python3 - "$OUT" <<'PY'
import glob, json, os, sys

out = sys.argv[1]
full = {json.loads(l)["case"]: json.loads(l) for l in open(out + "/full.jsonl")}
print()
print(f"{'bullet':36} {'cases':>5} {'full right':>10} {'minus right':>11} {'flipped':>8}")
for path in sorted(glob.glob(out + "/minus-*.jsonl")):
    name = os.path.basename(path)[len("minus-"):-len(".jsonl")]
    rows = [json.loads(l) for l in open(path)]
    flips = sum(1 for r in rows if full[r["case"]]["verdict"] != r["verdict"])
    right_full = sum(1 for r in rows if full[r["case"]]["pass"])
    right_minus = sum(1 for r in rows if r["pass"])
    print(f"{name:36} {len(rows):>5} {right_full:>10} {right_minus:>11} {flips:>8}")
PY
