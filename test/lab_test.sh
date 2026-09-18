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
# does in the fixture repo: commit on main, land through a merge, do nothing, or
# die without a result.
cat > "$W/bin/claude" <<'EOF'
#!/bin/bash
[ "${1:-}" = "--version" ] && { echo "0.0.0 (fake)"; exit 0; }
case " $* " in *" --safe-mode "*)
    jq -n --arg r "Reasons. VERDICT: $FAKE_JUDGE" '{is_error: false, result: $r, total_cost_usd: 0.5}'
    exit 0 ;;
esac
# A nested review call, which the agent below makes through the lab's shim.
case "$*" in *"/code-review"*)
    printf '%s\n' "${CLAUDE_CODE_OAUTH_TOKEN:-}" > "$FAKE_DIR/nested-token"
    if [ "$FAKE_MODE" = nologin-text ]; then
        echo "Not logged in · Please run /login"
    elif [ "$FAKE_MODE" = nologin ]; then
        jq -n '{is_error: false, subtype: "success", result: "Not logged in · Please run /login", num_turns: 0, total_cost_usd: 0}'
    else
        jq -n '{is_error: false, subtype: "success", result: "No findings.", num_turns: 5, total_cost_usd: 0.2}'
    fi
    exit 0 ;;
esac
printf '%s\n' "$*" > "$FAKE_DIR/agent-args"
printf '%s\n' "$HOME" > "$FAKE_DIR/agent-home"
printf '%s\n' "${CLAUDE_CODE_OAUTH_TOKEN:-}" > "$FAKE_DIR/agent-token"
# Claude Code does not hand its own token to the agent's shell commands, so
# the nested call starts without one.
case "$FAKE_MODE" in nested|nologin|nologin-text)
    env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY claude -p "/code-review high x" --model claude-fake-review --output-format json >/dev/null ;;
esac
case "$FAKE_MODE" in
    dead) exit 1 ;;
    land) mkdir -p src && echo "exports.x = 1" > src/x.js && git rm -q .plans/toy.md \
              && git add -A && git commit -qm "feat: add x" ;;
    merge) git checkout -q -b hone/toy && mkdir -p src && echo "exports.x = 1" > src/x.js \
              && git rm -q .plans/toy.md && git add -A && git commit -qm "feat: add x" \
              && git checkout -q main && git merge -q --no-ff -m "Merge branch 'hone/toy'" hone/toy \
              && git branch -q -D hone/toy ;;
esac
echo '{"type":"system","subtype":"init"}'
jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "Bash", input: {command: "bash \"/p/scripts/worktree.sh\" land toy"}}]}}'
jq -cn '{type: "user", message: {content: [{type: "tool_result", content: "Do: run worktree.sh grant toy, then land again."}]}}'
jq -cn '{type: "result", subtype: "success", is_error: false, result: "final report",
         total_cost_usd: 1.5, num_turns: 3}'
# A real session ends when its stdin closes. Wait for that, and say that it came.
cat >/dev/null
echo seen > "$FAKE_DIR/eof-seen"
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
        LAB_SCENARIOS="$W/scenarios" LAB_OUT="${LAB_OUT_OVERRIDE:-$W/out}" LAB_POLL=1 \
        LAB_CREDENTIALS="${CRED:-$W/no-credentials.json}" bash "$LAB" "$@" 2>&1
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

rm -f "$W/eof-seen"; fresh; MODE=land lab toy >/dev/null
[ -e "$W/eof-seen" ] && ok "the session gets EOF on stdin and ends by itself" || bad "the session never saw EOF, so the harness had to kill it"

echo "== a check reads the commands the agent ran, not the prose around them =="
cp "$W/scenarios/toy/check.sh" "$W/check.sh.keep"
printf '%s\n' "agent_ran 'worktree\\.sh\"? land' 'the run reached land'" > "$W/scenarios/toy/check.sh"
fresh; MODE=land lab toy >/dev/null
[ "$(result toy .verdict)" = "pass" ] && ok "a quoted script path still matches" || bad "agent_ran should match a quoted path ($(cat "$W"/out/*/toy/checks.log))"
printf '%s\n' "agent_ran 'worktree\\.sh\"? grant' 'the run made a grant'" > "$W/scenarios/toy/check.sh"
fresh; MODE=land lab toy >/dev/null
[ "$(result toy .verdict)" = "fail" ] && ok "a command that only a message names does not match" || bad "agent_ran must not match prose in a tool result"

echo "== a broken check.sh is indeterminate, never a pass =="
printf 'landed\nif [ -n x ; then\n' > "$W/scenarios/toy/check.sh"
fresh; MODE=land lab toy >/dev/null
[ "$(result toy .verdict)" = "indeterminate" ] && ok "a syntax error in check.sh is indeterminate" || bad "a syntax error should be indeterminate (got $(result toy .verdict))"
printf 'landed\nworktree_remved\n' > "$W/scenarios/toy/check.sh"
fresh; MODE=land lab toy >/dev/null
[ "$(result toy .verdict)" = "indeterminate" ] && ok "an unknown helper in check.sh is indeterminate" || bad "an unknown helper should be indeterminate (got $(result toy .verdict))"
printf ':\n' > "$W/scenarios/toy/check.sh"
fresh; MODE=land lab toy >/dev/null
[ "$(result toy .verdict)" = "indeterminate" ] && ok "a check.sh that checks nothing is indeterminate" || bad "an empty check should be indeterminate (got $(result toy .verdict))"
cp "$W/check.sh.keep" "$W/scenarios/toy/check.sh"

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

echo "== measures and the ending reach result.json, and they decide nothing =="
cp "$W/scenarios/toy/check.sh" "$W/check.sh.keep"
printf '%s\n' "landed" "measure colour blue" "goal shade dark dark" > "$W/scenarios/toy/check.sh"
fresh; MODE=merge lab toy >/dev/null
[ "$(result toy '[.verdict,.measures.colour]|join(" ")')" = "pass blue" ] && ok "a measure is in the result, and the verdict ignores it" || bad "the result should carry colour=blue beside a pass (got $(result toy -c .measures))"
[ "$(result toy .measures.shade)" = "dark" ] && ok "a goal that holds passes and stays a measure" || bad "a held goal should pass and be measured (got $(result toy -c .measures))"
[ "$(result toy .ending)" = "landed hone/toy feat .plans,src" ] && ok "the ending names the branch, the commit types, and the places" || bad "the ending of a merged run is wrong: $(result toy .ending)"
[ "$(result toy '.measures | has("stop_actionable")')" = "false" ] && ok "a landed run gets no stop-report judge" || bad "only a stopped run should reach the stop-report judge"
printf '%s\n' "not_landed" > "$W/scenarios/toy/check.sh"
fresh; MODE=idle JUDGE=FAIL lab toy >/dev/null
[ "$(result toy '[.verdict,.ending,.measures.stop_actionable,.judge_cost_usd]|join(" ")')" = "fail stopped worktrees=0 no 0.5" ] \
    && ok "a stop report that hands over no action fails the run, and the judge's cost is kept" || bad "a stopped run with a FAIL from the stop judge should fail (got $(result toy -c '[.verdict,.ending,.measures,.judge_cost_usd]'))"
JUDGE=PASS lab --regrade "$(echo "$W"/out/*/)" >/dev/null
[ "$(result toy .measures.stop_actionable)" = "no" ] && ok "a regrade keeps the stop-report answer that the run got" || bad "a regrade must not judge the same report again (got $(result toy .measures.stop_actionable))"

echo "== revertible: one merge that one revert undoes =="
printf '%s\n' "revertible" > "$W/scenarios/toy/check.sh"
fresh; MODE=merge lab toy >/dev/null
[ "$(result toy .verdict)" = "pass" ] && ok "a change that landed as one merge is revertible" || bad "one merge should be revertible ($(cat "$W"/out/*/toy/checks.log))"
fresh; MODE=land lab toy >/dev/null
[ "$(result toy .verdict)" = "fail" ] && grep -q 'not a merge' "$W"/out/*/toy/checks.log && ok "a commit made directly on main is not" || bad "a direct commit should fail revertible ($(cat "$W"/out/*/toy/checks.log))"
fresh; MODE=merge lab toy >/dev/null
touch "$(echo "$W"/out/*/toy/repo)/stray.txt"
lab --regrade "$(echo "$W"/out/*/)" >/dev/null
[ "$(result toy .verdict)" = "fail" ] && grep -q "outside git's record" "$W"/out/*/toy/checks.log && ok "a file that git does not track is something a revert cannot undo" || bad "an untracked file should fail revertible ($(cat "$W"/out/*/toy/checks.log))"
cp "$W/check.sh.keep" "$W/scenarios/toy/check.sh"

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
fresh; MODE=idle lab toy --without deny-rules,nag >/dev/null
[ "$(jq -c '.permissions.deny' "$W"/out/*/toy/repo/.claude/settings.json)" = "[]" ] && ok "--without deny-rules seeds the fixture with no deny rule" || bad "the fixture should have no deny rule"
grep -q '/nag\.sh' "$W"/out/*/toy/plugin/hooks/hooks.json && bad "nag.sh should be off beside deny-rules" || ok "a hook and the deny rules switch off together"
fresh; MODE=idle lab toy >/dev/null
[ "$(jq '.permissions.deny | length' "$W"/out/*/toy/repo/.claude/settings.json)" -gt 5 ] && ok "the full fixture carries the canonical deny rules" || bad "the fixture should carry the deny rules"
lab toy --without no-such-hook >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown hook name exits 2" || bad "an unknown hook should exit 2 (got $rc)"

echo "== the sandbox =="
fresh; MODE=land lab toy >/dev/null
[ "$(result toy .home)" = "shared" ] && ok "without a token in the environment the home is shared" || bad "home should be shared without a token"
fresh; TOKEN=fake MODE=land lab toy >/dev/null
[ "$(result toy .home)" = "isolated" ] && ok "with a token the home is isolated" || bad "home should be isolated with a token"
case "$(cat "$W/agent-home")" in "$W"/out/*/toy/home) ok "the agent runs with HOME inside the sandbox" ;; *) bad "HOME should point into the sandbox (got $(cat "$W/agent-home"))" ;; esac

echo "== the session token: OAuth auth with an isolated home =="
jq -n --argjson exp "$(( ($(date +%s) + 7200) * 1000 ))" \
    '{claudeAiOauth: {accessToken: "tok-from-file", refreshToken: "never-copy-me", expiresAt: $exp}}' > "$W/cred.json"
fresh; CRED="$W/cred.json" MODE=land lab toy >/dev/null
[ "$(result toy .home)" = "isolated" ] && ok "a credentials file with a live token isolates the home" || bad "home should be isolated with a session token"
[ "$(cat "$W/agent-token")" = "tok-from-file" ] && ok "the agent gets the access token through the environment" || bad "the agent should get the access token (got '$(cat "$W/agent-token")')"
grep -rqE 'tok-from-file|never-copy-me' "$W/out" && bad "a token reached the output directory" || ok "no token is written under the output directory"
fresh; CRED="$W/cred.json" MODE=nested lab toy >/dev/null
[ "$(cat "$W/nested-token")" = "tok-from-file" ] && ok "the shim gives a nested call the token that Claude Code withholds" || bad "a nested call should get the token (got '$(cat "$W/nested-token")')"
[ "$(result toy .nested_cost_usd)" = "0.2" ] && ok "the result carries the nested cost" || bad "nested cost should be 0.2"
[ "$(result toy .measures.reviews)" = "1" ] && ok "the result counts the nested reviews" || bad "measures.reviews should be 1 (got $(result toy -c .measures))"
grep -rqE 'tok-from-file' "$W/out" && bad "the token reached the output directory through the shim" || ok "the shim holds no token"
fresh; CRED="$W/cred.json" MODE=nologin lab toy >/dev/null; rc=$?
[ "$rc" -eq 3 ] && [ "$(result toy .verdict)" = "indeterminate" ] && ok "a nested call that is not logged in makes the run indeterminate" || bad "a nested login failure should give indeterminate (exit $rc, $(result toy .verdict))"
fresh; CRED="$W/cred.json" MODE=nologin-text lab toy >/dev/null
[ "$(result toy .verdict)" = "indeterminate" ] && ok "a login failure in plain text is indeterminate too" || bad "a plain-text login failure should give indeterminate (got $(result toy .verdict))"
jq -n --argjson exp "$(( ($(date +%s) + 60) * 1000 ))" \
    '{claudeAiOauth: {accessToken: "tok-stale", refreshToken: "never-copy-me", expiresAt: $exp}}' > "$W/cred.json"
fresh; CRED="$W/cred.json" MODE=land lab toy >/dev/null; rc=$?
[ "$rc" -eq 3 ] && [ "$(result toy .verdict)" = "indeterminate" ] && ok "a token that is about to expire makes the run indeterminate" || bad "a stale token should give indeterminate (exit $rc)"

echo "== --review-model moves the pin of the review command, in the sandbox only =="
fresh; MODE=nested lab toy --review-model claude-other-9 >/dev/null
grep -A6 -F 'claude -p "/code-review' "$W"/out/*/toy/plugin/skills/run/SKILL.md | grep -q -- '--model claude-other-9 ' \
    && ok "the sandboxed review command names the new model" || bad "the sandboxed run skill should pin claude-other-9"
grep -q 'claude-other-9' "$PLUGIN_ROOT/skills/run/SKILL.md" && bad "the repo's run skill must not change" || ok "the repo's run skill is untouched"
[ "$(result toy .review_model)" = "claude-fake-review" ] && ok "the result records the model that the nested call named" || bad "review_model should be claude-fake-review (got $(result toy .review_model))"
grep -q 'No findings' "$W"/out/*/toy/nested-out/*.out && ok "the output of the nested call is kept" || bad "nested-out/ should hold the review's output"
cp "$W/scenarios/toy/check.sh" "$W/check.sh.keep"
printf '%s\n' "unchanged scripts/run-tests.sh" "review_named 'no findings'" > "$W/scenarios/toy/check.sh"
lab --regrade "$(echo "$W"/out/*/)" >/dev/null
[ "$(result toy .measures.review_named)" = "yes" ] && ok "a check can read what the review said" || bad "review_named should measure yes"
[ "$(result toy .measures.brief_named)" = "no" ] && ok "a check can read what the run told the review" || bad "brief_named should measure that the brief was silent"
printf '%s\n' "review_named 'x'" > "$W/scenarios/toy/check.sh"
lab --regrade "$(echo "$W"/out/*/)" >/dev/null
[ "$(result toy .verdict)" = "indeterminate" ] && ok "a check.sh with measures alone made no check" || bad "measures alone should give indeterminate (got $(result toy .verdict))"
cp "$W/check.sh.keep" "$W/scenarios/toy/check.sh"
lab toy --review-model opus >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an alias for --review-model exits 2" || bad "a review-model alias should exit 2 (got $rc)"

echo "== the output directory must not sit below an instruction file =="
mkdir -p "$W/project/.claude/rules" "$W/project/deep/out"
out=$(LAB_OUT_OVERRIDE="$W/project/deep/out" lab toy); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '.claude/rules' && ok "an output directory below .claude/rules exits 2 and names it" || bad "a contaminated output directory should exit 2 (got $rc: $out)"
[ -z "$(ls -d "$W/project/deep/out/"*/toy 2>/dev/null)" ] && ok "no scenario ran there" || bad "no scenario should run below an instruction file"

echo "== reached reads a denial or a first write outside a worktree =="
tool_use() { jq -cn --arg p "$1" '{type: "assistant", message: {content: [{type: "tool_use", name: "Edit", input: {file_path: $p}}]}}'; }
reached_of() { LAB_TRANSCRIPT="$W/t.jsonl" bash -c "source '$PLUGIN_ROOT/evals/lab/checks.sh'; reached" | tr -d ' '; }
{ tool_use /x/repo/.worktrees/a/src/a.js; tool_use /x/repo/src/a.js; } > "$W/t.jsonl"
[ "$(reached_of)" = "measurereached=no" ] && ok "a first write in a worktree is no reach" || bad "a worktree write should measure no (got $(reached_of))"
tool_use /x/repo/src/a.js > "$W/t.jsonl"
[ "$(reached_of)" = "measurereached=yes" ] && ok "a first write under src/ of the primary tree is a reach" || bad "a primary-tree write should measure yes (got $(reached_of))"
{ tool_use /x/repo/.worktrees/a/src/a.js; echo '{"type":"user","text":"hone bash-guard: this command writes to the primary tree"}'; } > "$W/t.jsonl"
[ "$(reached_of)" = "measurereached=yes" ] && ok "a guard's denial that names the primary tree is a reach" || bad "a denial should measure yes (got $(reached_of))"

lab toy --model opus >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an alias for --model exits 2" || bad "a model alias should exit 2 (got $rc)"
lab no-such-scenario >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown scenario exits 2" || bad "an unknown scenario should exit 2 (got $rc)"

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
