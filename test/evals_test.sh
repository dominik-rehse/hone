#!/bin/bash
# Mechanical proof of the machine-drivable mode of evals/run.sh: the case
# subset, the candidate prompt, the JSON records, the response cache, and the
# model pin. A fake `claude` on PATH answers every call, so this test makes no
# model calls. It proves the plumbing only. What a real model answers is what
# the eval suite itself measures. Run: bash test/evals_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN="$PLUGIN_ROOT/evals/run.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/sys"

# The fake CLI. It answers the isolation probe with CANNOT READ and every
# other prompt with $FAKE_REPLY. It saves each system prompt it receives, and
# it reports one model ID in modelUsage, as the real envelope does.
cat > "$W/bin/claude" <<'EOF'
#!/bin/bash
[ "${1:-}" = "--version" ] && { echo "0.0.0 (fake)"; exit 0; }
prompt=""; sys=""; model=""
while [ $# -gt 0 ]; do
    case "$1" in
        -p) shift; prompt="$1" ;;
        --append-system-prompt) shift; sys="$1" ;;
        --model) shift; model="$1" ;;
    esac
    shift
done
case "$model" in claude-*) id="$model" ;; *) id="claude-$model-1" ;; esac
[ -n "${FAKE_NO_USAGE:-}" ] && id="claude-other-1"
case "$prompt" in
    *"CANNOT READ"*) reply="CANNOT READ" ;;
    *) [ -n "${FAKE_EMPTY:-}" ] && exit 1   # a failed call: no envelope at all
       reply="$FAKE_REPLY"
       n=$(find "$FAKE_DIR/sys" -type f | wc -l)
       printf '%s' "$sys" > "$FAKE_DIR/sys/$n.$$" ;;
esac
jq -n --arg r "$reply" --arg id "$id" \
    '{is_error: false, subtype: "success", result: $r, total_cost_usd: 0.25,
      modelUsage: {($id): {}, "claude-haiku-4-5-20251001": {}}}'
EOF
chmod +x "$W/bin/claude"

# Run the harness against the fake CLI, with the cache in the scratch dir.
run() {
    PATH="$W/bin:$PATH" FAKE_DIR="$W" FAKE_REPLY="${REPLY_TEXT:-}" \
        HONE_EVAL_CACHE="$W/cache" bash "$RUN" "$@" 2>&1
}
case_calls() { find "$W/sys" -type f | wc -l; }

# One real visible case supplies the brief and the expected token.
CASE=""
for d in "$PLUGIN_ROOT"/evals/plan-critic/*/; do
    case "$d" in *-holdout/|*-watch/) continue ;; esac
    CASE=$(basename "$d"); break
done
WANT=$(head -1 "$PLUGIN_ROOT/evals/plan-critic/$CASE/expected" | tr -d '[:space:]')
MUST=$(tail -n +2 "$PLUGIN_ROOT/evals/plan-critic/$CASE/expected" | tr '\n' ' ')
REPLY_TEXT="Findings: none. $MUST
VERDICT: $WANT"

echo "== --cases: a subset of one target =="
out=$(run plan-critic --model fake --cases "$CASE")
printf '%s\n' "$out" | grep -q "running 1 model call" && ok "one named case makes one call" || bad "--cases should run one call (got: $out)"
printf '%s\n' "$out" | grep -qE "ok +$CASE " && ok "the named case scores" || bad "the named case should pass on the fake reply"
run plan-critic --model fake --cases no-such-case >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown case name exits 2" || bad "an unknown case should exit 2 (got $rc)"

echo "== a -watch case runs only when --cases names it =="
WATCH=""
for d in "$PLUGIN_ROOT"/evals/*/*-watch/; do [ -f "$d/brief.md" ] && { WATCH=$(basename "$d"); WTARGET=$(basename "$(dirname "$d")"); break; }; done
if [ -n "$WATCH" ]; then
    # Capture first: under pipefail a `grep -q` that exits early fails the pipe.
    wout=$(run "$WTARGET" --model fake --dry-run)
    grep -q "$WATCH" <<<"$wout" && bad "a plain run should skip $WATCH" || ok "a plain run skips the watch case"
    wout=$(run "$WTARGET" --model fake --holdout --dry-run)
    grep -q "$WATCH" <<<"$wout" && bad "--holdout should not pull in $WATCH" || ok "--holdout does not pull it in"
    wout=$(run "$WTARGET" --model fake --cases "$WATCH" --dry-run)
    grep -q "$WATCH" <<<"$wout" && ok "--cases runs it" || bad "--cases $WATCH should run the watch case"
else
    bad "no -watch case exists to test the rule with"
fi

echo "== the model pin =="
printf '%s\n' "$out" | grep -q "model=claude-fake-1" && ok "the header carries the resolved model ID" || bad "the header should name claude-fake-1"
FAKE_NO_USAGE=1 run plan-critic --model fake --cases "$CASE" >/dev/null; rc=$?
[ "$rc" -eq 3 ] && ok "an alias that does not resolve exits 3" || bad "an unresolved alias should exit 3 (got $rc)"

SHIPS=$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^model:/{print $2}' "$PLUGIN_ROOT/agents/plan-critic.md")
printf '%s\n' "$out" | grep -q "plan-critic ships on $SHIPS" && ok "a run on another model than the critic ships on says so" || bad "a model mismatch should print a note"
out=$(run plan-critic --cases "$CASE")
printf '%s\n' "$out" | grep -qE "model=$SHIPS( |$)|\(from $SHIPS\)" && ok "the default model is the one the critics ship on" || bad "the default model should be $SHIPS"
printf '%s\n' "$out" | grep -q "ships on" && bad "a run on the shipped model should print no note" || ok "a run on the shipped model prints no note"

echo "== --prompt-file: a candidate prompt =="
printf -- '---\nname: candidate\n---\nCANDIDATE-MARKER body\n' > "$W/candidate.md"
rm -f "$W"/sys/*
run plan-critic --model fake --cases "$CASE" --prompt-file "$W/candidate.md" >/dev/null
grep -q "CANDIDATE-MARKER" "$W"/sys/* && ok "the candidate reaches the system slot" || bad "the system prompt should be the candidate"
grep -q "name: candidate" "$W"/sys/* && bad "the candidate's frontmatter should be stripped" || ok "the candidate's frontmatter is stripped"
run all --model fake --prompt-file "$W/candidate.md" >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "--prompt-file without one target exits 2" || bad "--prompt-file with all should exit 2 (got $rc)"
run plan-critic --model fake --ablate --prompt-file "$W/candidate.md" >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "--prompt-file with --ablate exits 2" || bad "--prompt-file with --ablate should exit 2 (got $rc)"

echo "== --json: one record per case × vote =="
run plan-critic --model fake --cases "$CASE" --votes 2 --json "$W/out.jsonl" >/dev/null
[ "$(wc -l < "$W/out.jsonl")" -eq 2 ] && ok "two votes give two records" || bad "--json should write one record per vote"
rec=$(head -1 "$W/out.jsonl")
[ "$(jq -r .reply <<<"$rec")" = "$REPLY_TEXT" ] && ok "the record carries the full reply" || bad "the record should carry the full reply"
[ "$(jq -r '[.target,.case,.expected,.token,.model]|join(" ")' <<<"$rec")" = "plan-critic $CASE $WANT $WANT claude-fake-1" ] \
    && ok "the record names target, case, expected, token, and model" || bad "record fields are wrong (got $rec)"
[ "$(jq -r '[.pass,.cached,.cost_usd]|join(" ")' <<<"$rec")" = "true false 0.25" ] && ok "the record carries pass, cached, and cost" || bad "pass/cached/cost are wrong (got $rec)"

echo "== a failed call keeps its record and does not break the cost line =="
out=$(FAKE_EMPTY=1 run plan-critic --model fake --cases "$CASE" --json "$W/empty.jsonl")
[ "$(jq -r '[.token,.cost_usd]|join(" ")' "$W/empty.jsonl" 2>/dev/null)" = " 0" ] && ok "a vote with no envelope still gets a record, at cost 0" || bad "the failed vote has no record (file: $(cat "$W/empty.jsonl" 2>/dev/null))"
grep -q '^cost: \$0\.00 for 1 call' <<<"$out" && ! grep -q 'jq: ' <<<"$out" && ok "the cost line survives a failed call" || bad "the cost line broke: $(grep -E '^cost|jq:' <<<"$out" | head -2)"

echo "== a run that would call nothing is a usage error =="
HOLD=""
for d in "$PLUGIN_ROOT"/evals/plan-critic/*-holdout/; do [ -f "$d/brief.md" ] && HOLD=$(basename "$d"); done
run plan-critic --model fake --cases "$HOLD" >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "a held-out name without --holdout exits 2" || bad "--cases $HOLD without --holdout should exit 2 (got $rc)"
run plan-critic --model fake --cases "$HOLD" --holdout >/dev/null; rc=$?
[ "$rc" -ne 2 ] && ok "with --holdout the same name runs" || bad "--cases $HOLD --holdout should run"

echo "== a loop run on a defaulted model says so =="
LCASE=$(basename "$(ls -d "$PLUGIN_ROOT"/evals/loop/*/ | grep -v -- '-holdout/' | head -1)")
out=$(run loop --cases "$LCASE")
grep -q 'NOTE: no --model' <<<"$out" && ok "a loop run without --model prints a note" || bad "loop without --model should print a note"
out=$(run loop --model fake --cases "$LCASE")
grep -q 'NOTE: no --model' <<<"$out" && bad "an explicit --model needs no note" || ok "an explicit --model prints no such note"

echo "== --cache: a repeated call costs nothing =="
rm -f "$W"/sys/*
run plan-critic --model fake --cases "$CASE" --votes 2 --cache >/dev/null
[ "$(case_calls)" -eq 2 ] && ok "a cold cache calls the model per vote" || bad "a cold cache should make 2 calls (made $(case_calls))"
run plan-critic --model fake --cases "$CASE" --votes 2 --cache --json "$W/hit.jsonl" >/dev/null
[ "$(case_calls)" -eq 2 ] && ok "a warm cache makes no call" || bad "a warm cache should make no new call (total $(case_calls))"
[ "$(jq -r .cached "$W/hit.jsonl" | sort -u)" = "true" ] && ok "the record marks a cached reply" || bad "a cache hit should record cached=true"
run plan-critic --model fake --cases "$CASE" --votes 2 --cache --prompt-file "$W/candidate.md" >/dev/null
[ "$(case_calls)" -eq 4 ] && ok "another prompt misses the cache" || bad "a changed prompt should miss the cache (total $(case_calls))"
rm -f "$W"/sys/*
run plan-critic --model fake --cases "$CASE" >/dev/null
[ "$(case_calls)" -eq 1 ] && ok "without --cache every run calls the model" || bad "the cache should be opt-in"

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
