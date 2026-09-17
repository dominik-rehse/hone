#!/bin/bash
# Mechanical proof of the scenario lab's harness (evals/lab/run.sh): the
# sandbox, the three-valued verdict, the judge, the ablation switch, and the
# cost record. A fake `claude` on PATH plays the agent, so this test makes no
# model calls. It proves the plumbing only. What a real run does is what the
# lab itself measures. Run: bash test/lab_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
LAB="$PLUGIN_ROOT/evals/lab/run.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

command -v npm >/dev/null 2>&1 || { echo "  SKIP: npm not available"; exit 0; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/scenarios/toy" "$W/scenarios/toy-judged"

# The fake CLI. A judge call carries --safe-mode, and it answers with
# $FAKE_JUDGE. Any other call is the agent. $FAKE_MODE picks what the agent
# does in the fixture repo: land a change, do nothing, or die without a result.
cat > "$W/bin/claude" <<'EOF'
#!/bin/bash
[ "${1:-}" = "--version" ] && { echo "0.0.0 (fake)"; exit 0; }
case " $* " in *" --safe-mode "*)
    jq -n --arg r "Reasons. VERDICT: $FAKE_JUDGE" '{is_error: false, result: $r, total_cost_usd: 0.5}'
    exit 0 ;;
esac
printf '%s\n' "$*" > "$FAKE_DIR/agent-args"
printf '%s\n' "$HOME" > "$FAKE_DIR/agent-home"
case "$FAKE_MODE" in
    dead) exit 1 ;;
    land) mkdir -p src && echo "exports.x = 1" > src/x.js && git rm -q .plans/toy.md \
              && git add -A && git commit -qm "feat: add x" ;;
esac
echo '{"type":"system","subtype":"init"}'
jq -cn '{type: "result", subtype: "success", is_error: false, result: "final report",
         total_cost_usd: 1.5, num_turns: 3}'
EOF
chmod +x "$W/bin/claude"

for s in toy toy-judged; do
    echo behavioral > "$W/scenarios/$s/track"
    echo "/hone:run toy" > "$W/scenarios/$s/prompt"
    cat > "$W/scenarios/$s/seed.sh" <<'EOF'
mkdir -p .plans && echo "# Plan: toy" > .plans/toy.md
EOF
    cat > "$W/scenarios/$s/check.sh" <<'EOF'
landed
plan_deleted toy
unchanged scripts/run-tests.sh
EOF
done
echo "Is the change fine?" > "$W/scenarios/toy-judged/judge.md"

# Run the lab against the fake CLI, with scenarios and output in the scratch dir.
lab() {
    env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN ${TOKEN:+ANTHROPIC_API_KEY="$TOKEN"} \
        PATH="$W/bin:$PATH" FAKE_DIR="$W" FAKE_MODE="${MODE:-land}" FAKE_JUDGE="${JUDGE:-PASS}" \
        LAB_SCENARIOS="$W/scenarios" LAB_OUT="$W/out" LAB_POLL=1 bash "$LAB" "$@" 2>&1
}
result() { jq -r "$2" "$W"/out/*/"$1"/result.json; }
fresh() { rm -rf "$W/out"; }

echo "== a run that lands passes =="
fresh; out=$(MODE=land lab toy); rc=$?
[ "$rc" -eq 0 ] && ok "a passing lab exits 0" || bad "a passing lab should exit 0 (got $rc: $out)"
[ "$(result toy .verdict)" = "pass" ] && ok "the verdict is pass" || bad "the verdict should be pass (got $(result toy .verdict))"
[ "$(result toy .cost_usd)" = "1.5" ] && ok "the result carries the run's cost" || bad "the cost should be 1.5"
[ -s "$W"/out/*/toy/transcript.jsonl ] && ok "the transcript is kept" || bad "the transcript should be kept"
grep -q -- "--plugin-dir $W/out/.*/toy/plugin" "$W/agent-args" && ok "the agent loads the sandboxed plugin copy" || bad "the agent should load the sandboxed plugin"
grep -q -- "--setting-sources project,local" "$W/agent-args" && ok "user-level settings stay out" || bad "the agent should run with project and local settings only"

echo "== a run that does not reach the terminal state fails =="
fresh; MODE=idle lab toy >/dev/null; rc=$?
[ "$rc" -eq 1 ] && ok "a failing lab exits 1" || bad "a failing lab should exit 1 (got $rc)"
[ "$(result toy .verdict)" = "fail" ] && ok "the verdict is fail" || bad "the verdict should be fail"
grep -q "FAIL" "$W"/out/*/toy/checks.log && ok "the check log names what failed" || bad "checks.log should name the failed check"

echo "== a broken run is indeterminate, never a behavioral result =="
fresh; MODE=dead lab toy >/dev/null; rc=$?
[ "$rc" -eq 3 ] && ok "an indeterminate lab exits 3" || bad "an indeterminate lab should exit 3 (got $rc)"
[ "$(result toy .verdict)" = "indeterminate" ] && ok "the verdict is indeterminate" || bad "the verdict should be indeterminate"

echo "== the judge decides what the checks cannot =="
fresh; MODE=land JUDGE=FAIL lab toy-judged >/dev/null
[ "$(result toy-judged .verdict)" = "fail" ] && ok "a judge FAIL fails a run whose checks pass" || bad "a judge FAIL should fail the run"
fresh; MODE=land JUDGE=PASS lab toy-judged >/dev/null
[ "$(result toy-judged '[.verdict,.judge_cost_usd]|join(" ")')" = "pass 0.5" ] && ok "a judge PASS passes, and its cost is separate" || bad "judge PASS should give pass with judge cost 0.5"
fresh; MODE=idle JUDGE=PASS lab toy-judged >/dev/null
[ "$(result toy-judged '[.verdict,.judge_cost_usd]|join(" ")')" = "fail 0" ] && ok "a failed check never reaches the judge" || bad "the judge should not run after a failed check"

echo "== --regrade grades a kept sandbox again, with no new run =="
fresh; MODE=idle lab toy >/dev/null
cp "$W/scenarios/toy/check.sh" "$W/check.sh.keep"
echo 'unchanged scripts/run-tests.sh' > "$W/scenarios/toy/check.sh"
rm -f "$W/agent-args"
lab --regrade "$(echo "$W"/out/*/)" >/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ "$(result toy .verdict)" = "pass" ] && ok "a changed check gives a new verdict" || bad "regrade should pass under the new check (exit $rc, $(result toy .verdict))"
[ ! -e "$W/agent-args" ] && ok "a regrade calls no agent" || bad "a regrade must not run the agent"
[ "$(result toy .cost_usd)" = "1.5" ] && ok "a regrade keeps the cost of the run" || bad "the regraded result should keep cost 1.5"
cp "$W/check.sh.keep" "$W/scenarios/toy/check.sh"

echo "== --without switches a hook off in the sandbox only =="
fresh; MODE=land lab toy --without guard >/dev/null
grep -q '/guard\.sh' "$W"/out/*/toy/plugin/hooks/hooks.json && bad "the sandboxed hooks.json should not wire guard.sh" || ok "the sandboxed hooks.json drops guard.sh"
grep -q 'bash-guard\.sh' "$W"/out/*/toy/plugin/hooks/hooks.json && ok "the other hooks stay wired" || bad "bash-guard.sh should stay wired"
grep -q '/guard\.sh' "$PLUGIN_ROOT/hooks/hooks.json" && ok "the repo's own hooks.json is untouched" || bad "the repo's hooks.json must not change"
[ "$(result toy .without)" = "guard" ] && ok "the result records the switch" || bad "the result should record --without"
lab toy --without no-such-hook >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown hook name exits 2" || bad "an unknown hook should exit 2 (got $rc)"

echo "== the sandbox =="
fresh; MODE=land lab toy >/dev/null
[ "$(result toy .home)" = "shared" ] && ok "without a token in the environment the home is shared" || bad "home should be shared without a token"
fresh; TOKEN=fake MODE=land lab toy >/dev/null
[ "$(result toy .home)" = "isolated" ] && ok "with a token the home is isolated" || bad "home should be isolated with a token"
case "$(cat "$W/agent-home")" in "$W"/out/*/toy/home) ok "the agent runs with HOME inside the sandbox" ;; *) bad "HOME should point into the sandbox (got $(cat "$W/agent-home"))" ;; esac
lab toy --model opus >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an alias for --model exits 2" || bad "a model alias should exit 2 (got $rc)"
lab no-such-scenario >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown scenario exits 2" || bad "an unknown scenario should exit 2 (got $rc)"

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
