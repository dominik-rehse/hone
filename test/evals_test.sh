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
    *) reply="$FAKE_REPLY"
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
    case "$d" in *-holdout/) continue ;; esac
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

echo "== the model pin =="
printf '%s\n' "$out" | grep -q "model=claude-fake-1" && ok "the header carries the resolved model ID" || bad "the header should name claude-fake-1"
FAKE_NO_USAGE=1 run plan-critic --model fake --cases "$CASE" >/dev/null; rc=$?
[ "$rc" -eq 3 ] && ok "an alias that does not resolve exits 3" || bad "an unresolved alias should exit 3 (got $rc)"

SHIPS=$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^model:/{print $2}' "$PLUGIN_ROOT/agents/plan-critic.md")
printf '%s\n' "$out" | grep -q "plan-critic ships on $SHIPS" && ok "a run on another model than the critic ships on says so" || bad "a model mismatch should print a note"
out=$(run plan-critic --cases "$CASE")
printf '%s\n' "$out" | grep -q "model=$SHIPS" && ok "the default model is the one the critics ship on" || bad "the default model should be $SHIPS"
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
