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
    land2) mkdir -p src && echo "exports.x = 1" > src/x.js && git rm -q .plans/toy.md \
              && git add -A && git commit -qm "feat: add x" \
              && echo "exports.y = 2" > src/y.js && git add -A && git commit -qm "feat: add y" ;;
    merge) git checkout -q -b hone/toy && mkdir -p src && echo "exports.x = 1" > src/x.js \
              && git rm -q .plans/toy.md && git add -A && git commit -qm "feat: add x" \
              && git checkout -q main && git merge -q --no-ff -m "Merge branch 'hone/toy'" hone/toy \
              && git branch -q -D hone/toy ;;
    # The sequence modes. Each call is one step, counted in seq-n. Step 2
    # lands nothing, which is the stop the driver has to carry. `seq-dead`
    # makes step 2 an infrastructure failure instead.
    seq|seq-dead)
        n=$(( $(cat "$FAKE_DIR/seq-n" 2>/dev/null || echo 0) + 1 ))
        echo "$n" > "$FAKE_DIR/seq-n"
        [ "$FAKE_MODE" = seq-dead ] && [ "$n" = 2 ] && exit 1
        if [ "$n" != 2 ]; then
            git checkout -q -b "hone/step-$n" && mkdir -p src && echo "exports.s = $n" > "src/s$n.js" \
                && git rm -q -r --ignore-unmatch .plans && git add -A && git commit -qm "feat: add s$n" \
                && git checkout -q main \
                && git merge -q --no-ff -m "Merge branch 'hone/step-$n'" "hone/step-$n" \
                && git branch -q -D "hone/step-$n"
        fi ;;
esac
echo '{"type":"system","subtype":"init"}'
jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "Bash", input: {command: "bash \"/p/scripts/worktree.sh\" land toy"}}]}}'
jq -cn '{type: "user", message: {content: [{type: "tool_result", content: "Do: run worktree.sh grant toy, then land again."}]}}'
jq -cn '{type: "result", subtype: "success", is_error: false, result: "final report",
         total_cost_usd: 1.5, num_turns: 3}'
# A real session ends when its stdin closes. Wait for that, and say that it
# came. The prompt arrives on stdin as stream-json, so this is also where a
# test reads the turn that the harness sent.
cat > "$FAKE_DIR/agent-stdin"
echo seen > "$FAKE_DIR/eof-seen"
EOF
chmod +x "$W/bin/claude"

for s in toy toy-judged; do
    echo behavioral > "$W/scenarios/$s/track"
    echo "/hone:run toy" > "$W/scenarios/$s/prompt"
    # The policy file is what the bare arm strips, beside the deny rules and
    # the gitignore lines that hone's setup wrote.
    cat > "$W/scenarios/$s/seed.sh" <<'EOF'
mkdir -p .plans && echo "# Plan: toy" > .plans/toy.md
echo 'config/' > .hone-irreversible-paths
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
cp "$W/scenarios/toy/prompt" "$W/prompt.keep"; echo "/hone:setup" > "$W/scenarios/toy/prompt"
fresh; MODE=idle JUDGE=FAIL lab toy >/dev/null
[ "$(result toy '[.verdict, (.measures | has("stop_actionable"))] | join(" ")')" = "pass false" ] \
    && ok "a session that is not the loop gets no stop-report judge" || bad "only a /hone:run session should reach the stop-report judge (got $(result toy -c '[.verdict,.measures]'))"
cp "$W/prompt.keep" "$W/scenarios/toy/prompt"

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
# Reversible is a condition of every variant, so the bare arm measures the
# outcome instead of failing on the shape of a land that it never makes.
fresh; MODE=land lab toy --bare >/dev/null
[ "$(result toy .verdict)" = "pass" ] && ok "on the bare arm one plain commit is revertible" || bad "a plain commit should be revertible on the bare arm ($(cat "$W"/out/*/toy/checks.log))"
fresh; MODE=land2 lab toy --bare >/dev/null
[ "$(result toy .verdict)" = "fail" ] && grep -q 'first-parent commits' "$W"/out/*/toy/checks.log \
    && ok "two commits are revertible on neither arm" || bad "two commits should fail revertible on the bare arm ($(cat "$W"/out/*/toy/checks.log))"
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

echo "== the result hashes the plugin copy once per shipped path =="
# The full run above is still in $W/out. evals/candidate.sh reads these hashes
# to compare two runs path by path.
full_files=$(result toy .plugin_files)
[ "$(jq -r '."hooks/guard.sh"' <<<"$full_files")" = "$(sha256sum "$W"/out/*/toy/plugin/hooks/guard.sh | cut -c1-12)" ] \
    && ok "the hash of a path is the hash of that file in the copy" || bad "the per-path hash should be the file's own hash"
[ "$(jq 'length' <<<"$full_files")" -gt 20 ] && ok "every file of the copy has an entry" || bad "the copy has more files than $(jq 'length' <<<"$full_files") entries"
fresh; MODE=idle lab toy --without guard >/dev/null
off_files=$(result toy .plugin_files)
[ "$(jq -r '."hooks/hooks.json"' <<<"$full_files")" != "$(jq -r '."hooks/hooks.json"' <<<"$off_files")" ] \
    && ok "a switched hook changes the hash of the file it edits" || bad "--without should change hooks.json"
[ "$(jq -r '."skills/plan/SKILL.md"' <<<"$full_files")" = "$(jq -r '."skills/plan/SKILL.md"' <<<"$off_files")" ] \
    && ok "it changes no other path" || bad "--without must not change the hash of another file"

lab toy --without no-such-hook >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown hook name exits 2" || bad "an unknown hook should exit 2 (got $rc)"

echo "== --bare runs the same scenario with no hone at all =="
prompt_sent() { jq -r '.message.content' "$W/agent-stdin"; }
fresh; MODE=land lab toy --bare >/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ "$(result toy .verdict)" = "pass" ] && ok "a bare run grades as any other" \
    || bad "a bare run should grade as any other (exit $rc, $(result toy .verdict))"
grep -q -- "--plugin-dir" "$W/agent-args" && bad "a bare session must load no plugin" || ok "the bare session gets no --plugin-dir"
[ -z "$(ls -d "$W"/out/*/toy/plugin 2>/dev/null)" ] && ok "no copy of the plugin is left in the sandbox" || bad "the sandbox still holds hone's own files"
[ "$(result toy '[.arm,.plugin]|join(" ")')" = "bare none" ] && ok "the result says which arm ran" \
    || bad "the result should say arm=bare and plugin=none (got $(result toy '[.arm,.plugin]|join(" ")'))"
[ "$(result toy .cost_usd)" = "1.5" ] && ok "the bare result carries cost and time as the full arm does" || bad "a bare run should carry its cost"
# The prompt: the brief that the seed wrote, and no slash command.
[ "$(prompt_sent | head -1)" = "# Plan: toy" ] && ok "the bare turn is the text of the scenario's brief" || bad "the bare turn should open with the brief (got $(prompt_sent | head -1))"
prompt_sent | grep -q '/hone:' && bad "the bare turn names a skill that the session does not have" || ok "the bare turn names no skill of hone"
prompt_sent | grep -q 'Make the change in this repository' && ok "the bare turn asks for the change" || bad "the bare turn should ask for the change"
# The fixture: the same code and task, with no trace of a hone setup.
sb=$(echo "$W"/out/*/toy)
[ "$(jq -c '.permissions.deny' "$sb/repo/.claude/settings.json")" = "[]" ] && ok "the bare fixture has no deny rule" || bad "the bare fixture should have no deny rule"
[ ! -e "$sb/repo/.hone-irreversible-paths" ] && ok "the bare fixture holds no policy file of hone" || bad "a hone policy file survived the strip"
grep -q 'worktrees' "$sb/repo/.gitignore" && bad "the bare fixture still gitignores hone's worktrees" || ok "the bare fixture gitignores nothing of hone"
# The seed commit, because the agent of this test deletes the Plan as a land does.
git -C "$sb/repo" cat-file -e "$(cat "$sb/base"):.plans/toy.md" 2>/dev/null \
    && ok "the brief stays in the tree, so a check on it reads a true zero" || bad "the seed should keep the brief"
[ -x "$sb/repo/scripts/run-tests.sh" ] && ok "the adapter stays, because the checks run it" || bad "the bare fixture should keep its adapter"

fresh; MODE=land lab toy >/dev/null
[ "$(result toy .arm)" = "full" ] && ok "a run with the plugin says arm=full" || bad "a full run should say arm=full (got $(result toy .arm))"
[ "$(prompt_sent | head -1)" = "/hone:run toy" ] && ok "the full arm sends the scenario's own prompt" || bad "the full arm should send the prompt file unchanged"

echo "== a scenario with no fair bare form is skipped, and skipped is no verdict about hone =="
for s in toy-plan toy-claim toy-nobrief; do
    mkdir -p "$W/scenarios/$s"
    cp "$W/scenarios/toy/check.sh" "$W/scenarios/$s/check.sh"
    echo behavioral > "$W/scenarios/$s/track"
    cp "$W/scenarios/toy/seed.sh" "$W/scenarios/$s/seed.sh"
    echo "/hone:run toy" > "$W/scenarios/$s/prompt"
done
echo "/hone:plan toy: a sketch" > "$W/scenarios/toy-plan/prompt"
# A seed that names hone's worktree helper leaves the fixture in a state that
# only hone can be in, so no bare session can meet it.
echo '# the real one calls worktree.sh add' >> "$W/scenarios/toy-claim/seed.sh"
echo "/hone:run absent" > "$W/scenarios/toy-nobrief/prompt"
for s in toy-plan toy-claim toy-nobrief; do
    fresh; rm -f "$W/agent-args"
    MODE=land lab "$s" --bare >/dev/null; rc=$?
    [ "$rc" -eq 0 ] && ok "a skipped scenario fails nothing ($s)" || bad "$s should exit 0 when it skips (got $rc)"
    [ "$(result "$s" .verdict)" = "skipped" ] && ok "the verdict of $s is skipped" || bad "$s should be skipped (got $(result "$s" .verdict))"
    [ -n "$(result "$s" .reason)" ] && ok "the result of $s says why" || bad "a skip should carry its reason"
    [ ! -e "$W/agent-args" ] && ok "a skipped scenario calls no agent ($s)" || bad "$s must not run the agent"
done
fresh; MODE=land lab toy-plan >/dev/null
[ "$(result toy-plan .verdict)" = "pass" ] && ok "the same scenario runs in the full arm" || bad "only the bare arm skips a /hone:plan scenario"

echo "== --bare and a switch of the plugin are not one arm =="
lab toy --bare --without guard >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "--bare with --without exits 2" || bad "--bare with --without should exit 2 (got $rc)"
lab toy --bare --review-model claude-other-9 >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "--bare with --review-model exits 2" || bad "--bare with --review-model should exit 2 (got $rc)"

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
# A token too short for a run is a reason to wait, not to fan out: every
# scenario would refuse at the margin. The fake CLI here never renews, so the
# wait runs out and the pass never starts.
jq -n --argjson exp "$(( ($(date +%s) + 60) * 1000 ))" \
    '{claudeAiOauth: {accessToken: "tok-stale", refreshToken: "never-copy-me", expiresAt: $exp}}' > "$W/cred.json"
fresh; out=$(CRED="$W/cred.json" MODE=land TOKEN_WAIT_STEP=1 TOKEN_WAIT_MAX=2 lab toy); rc=$?
[ "$rc" -eq 2 ] && ok "a token that will not renew stops the run before the fan-out" || bad "a token that will not renew should exit 2 (got $rc: $out)"
printf '%s' "$out" | grep -q 'Waiting for the CLI to renew it' && ok "the run says what it waits for" || bad "the run should name what it waits for (got: $out)"
[ -z "$(ls -d "$W"/out/*/toy 2>/dev/null)" ] && ok "no scenario runs on a token that would expire under it" || bad "no scenario should run on a stale token"

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

echo "== progress_lines counts the steps the run announced =="
say() { jq -cn --arg t "$1" '{type: "assistant", message: {content: [{type: "text", text: $t}]}}'; }
progress_of() { LAB_TRANSCRIPT="$W/t.jsonl" bash -c "source '$PLUGIN_ROOT/evals/lab/checks.sh'; progress_lines" | tr -d ' ' | tr '\n' ' '; }
{ say '`◆` `[a]` `worktree ...` > build > verify > consolidate > review > land'
  say 'Status. `◆` `[a]` worktree ✓ > `build ...` > verify > consolidate > review > land'
  say '`◆` `[a]` worktree ✓ > build ✓ > verify ✓ > consolidate ✓ > review ✓ > `land ✓ (merged 3f2a1c9)`'
  tool_use '/x/◆ verify ...'; } > "$W/t.jsonl"
[ "$(progress_of)" = "measureprogress_lines=3 measureprogress_starts=2/6 " ] \
    && ok "two announced starts of six reached steps, over three lines" || bad "progress should measure 3 lines and 2/6 (got $(progress_of))"
say 'I did the work.' > "$W/t.jsonl"
[ "$(progress_of)" = "measureprogress_lines=0 measureprogress_starts=0/0 " ] \
    && ok "a silent run measures no line" || bad "a silent run should measure 0 and 0/0 (got $(progress_of))"
say '`◆` `[a]` worktree ✓ > `build ✗` > verify > consolidate > review > land' > "$W/t.jsonl"
[ "$(progress_of)" = "measureprogress_lines=1 measureprogress_starts=0/2 " ] \
    && ok "a failed step counts as reached" || bad "a stop at build should measure 0/2 (got $(progress_of))"

echo "== a scenario with a by-name file stays out of a pass that names none =="
mkdir -p "$W/scenarios/toy-byname"
for f in track prompt seed.sh check.sh; do cp "$W/scenarios/toy/$f" "$W/scenarios/toy-byname/$f"; done
echo "it needs the network" > "$W/scenarios/toy-byname/by-name"
lab --dry-run | grep -q toy-byname && bad "a by-name scenario must not run in a pass that names none" || ok "a pass that names no scenario leaves it out"
lab --track behavioral --dry-run | grep -q toy-byname && bad "a track pass must not pick a by-name scenario" || ok "a track pass leaves it out too"
lab toy-byname --dry-run | grep -q toy-byname && ok "naming it runs it" || bad "a named by-name scenario should run"
rm -rf "$W/scenarios/toy-byname"

echo "== real-base-click: the seed's message, and the check's two end states =="
# The scenario fetches pallets/click at a pin. This test makes no model call and
# reaches no network: it uses the cached mirror when one is there, and it skips
# when there is none. The pin comes from the seed, so it is stated once.
RB="$PLUGIN_ROOT/evals/lab/scenarios/real-base-click"
PIN=$(sed -n 's/^PIN=\([0-9a-f]\{40\}\).*/\1/p' "$RB/seed.sh")
MIRROR="${LAB_BASE_CACHE:-/var/tmp/hone-lab-bases}/click.git"
bash -n "$RB/seed.sh" && ok "the seed of real-base-click parses" || bad "the seed of real-base-click has a syntax error"
bash -n "$RB/check.sh" && ok "the check of real-base-click parses" || bad "the check of real-base-click has a syntax error"
[ -f "$RB/by-name" ] && ok "real-base-click runs by name only" || bad "real-base-click should carry a by-name file"
# With an empty cache and no way out, the seed says what it needs and stops.
# The harness turns that into an indeterminate verdict, never into a fail.
mkdir -p "$W/rb/repo"
out=$( cd "$W/rb/repo" && LAB_BASE_CACHE="$W/rb/cache" LAB_PLUGIN="$PLUGIN_ROOT" \
       http_proxy=http://127.0.0.1:1 https_proxy=http://127.0.0.1:1 GIT_TERMINAL_PROMPT=0 \
       bash "$RB/seed.sh" 2>&1 ); rc=$?
[ "$rc" -ne 0 ] && ok "with no cache and no network the seed stops" || bad "the seed should stop without a base (got $rc)"
printf '%s' "$out" | grep -q 'needs the network once' && ok "and it says what it needs" || bad "the seed should name what it needs (got: $(printf '%s' "$out" | tail -1))"

if [ -n "$PIN" ] && git -C "$MIRROR" cat-file -e "$PIN^{commit}" 2>/dev/null && command -v python3 >/dev/null; then
    sed -n "/^cat > \"\$probe\" <<'PY'$/,/^PY$/p" "$RB/check.sh" | sed '1d;$d' > "$W/rb/probe.py"
    # Two end states by hand. The good one hands the values to the default map
    # of the context and asks the base where the per-user directory is. The
    # copied one places the values on the parameters itself and joins the path.
    cat > "$W/rb/impl.py" <<'PY'


def config_option(*param_decls, app_name, filename="config.json", **kwargs):
    import json
    import os

    from .exceptions import UsageError
    from .types import Path as PathType
    from .utils import get_app_dir

    def callback(ctx, param, value):
        if ctx.resilient_parsing:
            return
        if value is None:
            path = os.path.join(APPDIR, filename)
            if not os.path.isfile(path):
                return
        else:
            path = value
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError) as e:
            raise UsageError(f"Could not read {path}: {e}", ctx=ctx) from e
        if not isinstance(data, dict):
            raise UsageError(f"{path} holds no object", ctx=ctx)
        PLACE

    if not param_decls:
        param_decls = ("--config",)
    kwargs.setdefault("type", PathType(exists=True, dir_okay=False))
    kwargs.setdefault("expose_value", False)
    kwargs.setdefault("is_eager", True)
    kwargs["callback"] = callback
    return option(*param_decls, **kwargs)
PY
    end_state() {   # $1 the tree, $2 the app-dir expression, $3 the placement
        mkdir -p "$W/rb/$1" && git -C "$MIRROR" archive "$PIN" src | tar -x -C "$W/rb/$1"
        sed -e "s#APPDIR#$2#" -e "s#PLACE#$3#" "$W/rb/impl.py" >> "$W/rb/$1/src/click/decorators.py"
        echo 'from .decorators import config_option as config_option' >> "$W/rb/$1/src/click/__init__.py"
        ( cd "$W/rb/$1" && PYTHONPATH=src python3 -W ignore "$W/rb/probe.py" 2>&1 | tr '\n' '|' )
    }
    place_by_hand='[setattr(p, "default", v[p.name]) for k, v in data.items() if isinstance(v, dict) for p in getattr(ctx.command, "commands", {}).get(k, ctx.command).params if p.name in v]'
    good=$(end_state good 'get_app_dir(app_name)' 'ctx.default_map = dict(ctx.default_map or {}, **data)')
    copied=$(end_state copied 'os.path.join(os.path.expanduser("~/.config"), app_name)' "$place_by_hand")
    [ "$good" = "PROOF 5000 1234 7000 5000 5000 exit2 exit2 8000|SOURCE DEFAULT_MAP|APPDIR 4242|" ] \
        && ok "the proof and both measures read a good end state" || bad "the good end state should pass the proof (got $good)"
    case "$copied" in
        "PROOF 5000 1234 7000 5000 5000 exit2 exit2 8000|"*) bad "a copied end state should not pass the whole proof (got $copied)" ;;
        *"|SOURCE DEFAULT|APPDIR 3131|") ok "a copied end state fails the proof, and both measures say where it went" ;;
        *) bad "the copied end state should measure SOURCE DEFAULT and APPDIR 3131 (got $copied)" ;;
    esac
else
    echo "  SKIP: no cached click mirror at $MIRROR, so the end states are not built"
fi

lab toy --model opus >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an alias for --model exits 2" || bad "a model alias should exit 2 (got $rc)"
lab no-such-scenario >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown scenario exits 2" || bad "an unknown scenario should exit 2 (got $rc)"

echo
echo "== the variant builder (evals/lab/variant.py) =="
# One part at a time, off in a copy of the plugin. No model call: the builder
# reads evals/lab/parts.json and writes the copy that a run would load.
VB="$PLUGIN_ROOT/evals/lab/variant.py"
VW="$W/variant"; mkdir -p "$VW"
SHIPPED_DIRS=".claude-plugin agents hooks rules scripts skills templates"
shipped_hash() { ( cd "$1" && find $SHIPPED_DIRS -type f -print0 | sort -z \
    | xargs -0 sha256sum | sha256sum | cut -c1-16 ); }
plugin_copy() { mkdir -p "$2"; for d in $SHIPPED_DIRS; do cp -r "$1/$d" "$2/"; done; }
# Every file that differs between two copies, or that one of them lacks.
changed_files() {
    python3 - "$1" "$2" <<'PY'
import filecmp, os, sys
a, b = sys.argv[1], sys.argv[2]
out = []
for root, _, files in os.walk(a):
    for f in files:
        rel = os.path.relpath(os.path.join(root, f), a)
        pb = os.path.join(b, rel)
        if not os.path.exists(pb) or not filecmp.cmp(os.path.join(root, f), pb, shallow=False):
            out.append(rel)
print("\n".join(sorted(out)))
PY
}

repo_before=$(shipped_hash "$PLUGIN_ROOT")
python3 "$VB" --check >/dev/null 2>&1 \
    && ok "every anchor of parts.json still matches this repository" \
    || bad "an anchor of parts.json is stale: $(python3 "$VB" --check 2>&1 | tail -1)"

plugin_copy "$PLUGIN_ROOT" "$VW/base"
# What must be gone from the built copy, per part: a file, then a literal string.
part_gone() {
    case "$1" in
        guard|bash-guard|dirty-guard|gate|nag|session-start)
                             printf '%s\n' "hooks/hooks.json|/$1.sh" ;;
        plan-critic)         printf '%s\n' "skills/plan/SKILL.md|subagent_type: plan-critic" ;;
        consolidate-critic)  printf '%s\n' "skills/run/SKILL.md|subagent_type: consolidate-critic" ;;
        test-first)          printf '%s\n' "skills/run/SKILL.md|**Red.**" ;;
        verify)              printf '%s\n' "skills/run/SKILL.md|### 3. Verify" ;;
        consolidate)         printf '%s\n' "skills/run/SKILL.md|sort the leftovers" ;;
        review)              printf '%s\n' "skills/run/SKILL.md|/code-review" ;;
        land)                printf '%s\n' 'skills/run/SKILL.md|worktree.sh" land' ;;
        shape-gate)          printf '%s\n' "scripts/worktree.sh|grep -E '^(Cut|Repair): " ;;
        grant-gate)          printf '%s\n' 'scripts/worktree.sh|reasons=$(land_irreversible' ;;
        proof-gate)          printf '%s\n' 'scripts/worktree.sh|land_proof_required "$main_root"' ;;
    esac
}
for p in $(python3 "$VB" --parts | awk '$2 != "setting" && $2 != "fixture" {print $1}'); do
    sel="$p"; [ "$p" = test-first ] && sel="test-first,guard"
    plugin_copy "$PLUGIN_ROOT" "$VW/$p"
    if ! python3 "$VB" --plugin "$VW/$p" --without "$sel" 2> "$VW/$p.err"; then
        bad "the builder failed on '$p' ($(tail -1 "$VW/$p.err"))"; continue
    fi
    want=$(python3 "$VB" --touches --without "$sel")
    [ "$(changed_files "$VW/base" "$VW/$p")" = "$want" ] \
        && ok "'$p' off changes the files parts.json declares, and no other byte" \
        || bad "'$p' off changed $(changed_files "$VW/base" "$VW/$p" | tr '\n' ' '), declared: $(echo "$want" | tr '\n' ' ')"
    gone="$(part_gone "$p")"
    grep -qF -- "${gone#*|}" "$VW/$p/${gone%%|*}" \
        && bad "'$p' off still carries '${gone#*|}' in ${gone%%|*}" \
        || ok "'$p' off leaves no '${gone#*|}' in ${gone%%|*}"
done
bash -n "$VW/shape-gate/scripts/worktree.sh" && bash -n "$VW/proof-gate/scripts/worktree.sh" \
    && ok "a gate patch leaves a script bash can parse" || bad "a gate patch broke worktree.sh"
[ "$(shipped_hash "$PLUGIN_ROOT")" = "$repo_before" ] \
    && ok "no build touched a shipped file of this repository" || bad "the builder wrote into the repo"

echo "== a setting moves a model or a level, in the copy only =="
plugin_copy "$PLUGIN_ROOT" "$VW/set"
python3 "$VB" --plugin "$VW/set" --set review.level=low --set consolidate-critic.model=claude-fake-7
grep -q '/code-review low ' "$VW/set/skills/run/SKILL.md" && grep -q -- '--effort low' "$VW/set/skills/run/SKILL.md" \
    && ok "review.level moves the level in the prompt and in --effort" || bad "review.level should move both"
grep -q '^model: claude-fake-7$' "$VW/set/agents/consolidate-critic.md" \
    && ok "a critic's model is the frontmatter line of its agent" || bad "consolidate-critic.model should move the frontmatter"

echo "== the builder refuses what it cannot build honestly =="
vfail() { python3 "$VB" --check "$@" >/dev/null 2>&1; [ "$?" -eq 2 ]; }
vfail --without no-such-part && ok "an unknown part name exits 2" || bad "an unknown part should exit 2"
vfail --without test-first && ok "test-first off without guard off exits 2" || bad "test-first needs guard off"
vfail --without land,proof-gate && ok "a gate off inside a land that is off exits 2" || bad "land excludes its gates"
vfail --without review --set review.model=claude-x-1 && ok "a setting on a part that is off exits 2" || bad "a setting on an off part should exit 2"
vfail --set review.model=opus && ok "an alias for a model setting exits 2" || bad "a model alias should exit 2"
vfail --set review.level=deep && ok "an unknown review level exits 2" || bad "an unknown level should exit 2"
# A stale part map: a section name the skill no longer has, and an anchor the
# skill no longer carries. Both must fail before any copy is built.
python3 - "$PLUGIN_ROOT/evals/lab/parts.json" "$VW/stale-section.json" "$VW/stale-anchor.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
doc["parts"]["review"]["drop"][0]["sections"] = ["5-review-that-no-skill-has"]
json.dump(doc, open(sys.argv[2], "w", encoding="utf-8"))
doc = json.load(open(sys.argv[1], encoding="utf-8"))
doc["parts"]["review"]["sub"][0]["from"] = ["a sentence the run skill never carried"]
json.dump(doc, open(sys.argv[3], "w", encoding="utf-8"))
PY
env LAB_PARTS="$VW/stale-section.json" python3 "$VB" --check --without review >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a section name the skill no longer has exits 2" || bad "a stale section name should exit 2"
env LAB_PARTS="$VW/stale-anchor.json" python3 "$VB" --check --without review >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "an anchor the skill no longer carries exits 2" || bad "a stale anchor should exit 2"

echo "== a named variant file, and the variant in result.json =="
mkdir -p "$VW/files"
jq -n '{description: "the two dearest steps", off: ["review"], settings: {"consolidate-critic.model": "claude-fake-7"}}' \
    > "$VW/files/lean.json"
[ "$(env LAB_VARIANTS="$VW/files" python3 "$VB" --json --variant lean)" \
    = '{"off": ["review"], "settings": {"consolidate-critic.model": "claude-fake-7"}}' ] \
    && ok "a variant file resolves to its parts and its settings" || bad "the variant file did not resolve"
[ "$(python3 "$VB" --json --variant full)" = '{"off": [], "settings": {}}' ] \
    && ok "the shipped 'full' variant switches nothing off" || bad "variants/full.json should be empty"
env LAB_VARIANTS="$VW/files" python3 "$VB" --check --variant no-such-file >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "an unknown variant file exits 2" || bad "an unknown variant file should exit 2"

fresh; MODE=land lab toy --without consolidate-critic >/dev/null
[ "$(result toy '.variant.off | join(",")')" = "consolidate-critic" ] \
    && ok "result.json records the parts that were off" || bad "the result should carry the variant (got $(result toy -c .variant))"
[ ! -e "$(echo "$W"/out/*/toy)/plugin/agents/consolidate-critic.md" ] \
    && ok "the agent of a part that is off is gone from the sandboxed copy" || bad "the critic file survived in the sandbox"
[ -f "$PLUGIN_ROOT/agents/consolidate-critic.md" ] && ok "the repo's own agent is untouched" || bad "the repo's agent must not be removed"
fresh; MODE=land lab toy >/dev/null
[ "$(result toy '[(.variant.off | length), (.variant.settings | length)] | join(" ")')" = "0 0" ] \
    && ok "a run with nothing off records an empty variant" || bad "the full arm should record an empty variant"
fresh; MODE=nested lab toy --review-model claude-other-9 >/dev/null
[ "$(result toy '.variant.settings["review.model"]')" = "claude-other-9" ] \
    && ok "--review-model reaches the variant as a setting" || bad "--review-model should be a setting of the variant"

echo
echo "== the token wait (evals/session-token.sh) =="
# A fake CLI stands in for the renewal: it counts its calls, and on the call
# that $T/renew_on names it writes a fresh expiresAt, which is what the real
# CLI does in the last minutes of a token's life. No network, no credentials
# of the user: $T/creds.json is the whole world here.
T=$(mktemp -d); trap 'rm -rf "$W" "$T"' EXIT
cat > "$T/fake-claude" <<'EOF'
#!/bin/bash
n=$(( $(cat "$T/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$T/calls"
[ "$n" -ge "$(cat "$T/renew_on")" ] && jq '.claudeAiOauth.expiresAt = (now + 28800) * 1000' \
    "$T/creds.json" > "$T/creds.tmp" && mv "$T/creds.tmp" "$T/creds.json"
exit 0
EOF
chmod +x "$T/fake-claude"

# minutes_left: the token expires that many minutes from now. renew_on: the
# call that renews it, or a number past the cap for a CLI that never does.
token_case() {
    local minutes_left="$1" renew_on="$2"
    rm -f "$T/calls"; echo "$renew_on" > "$T/renew_on"
    jq -n --argjson m "$minutes_left" '{claudeAiOauth: {accessToken: "tok", expiresAt: ((now + $m * 60) * 1000 | floor)}}' \
        > "$T/creds.json"
    ( export T CREDENTIALS="$T/creds.json" REAL_CLAUDE="$T/fake-claude"
      export TOKEN_WAIT_STEP=1 TOKEN_WAIT_MAX=4
      . "$PLUGIN_ROOT/evals/session-token.sh"
      refresh_session_token > "$T/out" 2> "$T/err"; echo "$?" > "$T/rc" )
}
calls_made() { cat "$T/calls" 2>/dev/null || echo 0; }

token_case 120 99
[ "$(cat "$T/rc")" = 0 ] && [ "$(calls_made)" = 0 ] \
    && ok "a token that outlives the margin needs no call" \
    || bad "a fresh token should return 0 with no call (rc $(cat "$T/rc"), $(calls_made) call(s))"

token_case 10 2
[ "$(cat "$T/rc")" = 0 ] && ok "a stale token that renews on a later call returns 0" \
    || bad "a renewed token should return 0 (rc $(cat "$T/rc"))"
[ "$(calls_made)" -ge 2 ] && ok "the wait calls again until expiresAt moves" \
    || bad "the wait should call more than once (got $(calls_made))"
grep -q 'Waiting for the CLI to renew it' "$T/out" \
    && ok "the wait says on the terminal what it waits for" \
    || bad "the wait should name what it waits for (got: $(head -1 "$T/out"))"
grep -q 'renewed' "$T/out" && ok "the wait says that the token was renewed" \
    || bad "the wait should report the renewal (got: $(tail -1 "$T/out"))"

token_case 10 999
[ "$(cat "$T/rc")" = 1 ] && ok "a token that never renews fails the run" \
    || bad "a token that never renews should return 1 (rc $(cat "$T/rc"))"
[ -s "$T/err" ] && ok "the give-up line goes to stderr" \
    || bad "giving up should write to stderr"
# The old code refused here instead of waiting, and every scenario was lost.
[ "$(calls_made)" -ge 2 ] && ok "the wait retries before it gives up" \
    || bad "the wait should retry before giving up (got $(calls_made))"

echo
echo "== the generator of the transparent family =="
# evals/lab/generators/transparent.py writes scenarios from a seed number.
# Three claims, and no model call: one seed gives one scenario, two seeds give
# two, and what it writes is a scenario that run.sh accepts.
GEN="$PLUGIN_ROOT/evals/lab/generators/transparent.py"
G="$W/generated"
PYTHONDONTWRITEBYTECODE=1 python3 "$GEN" --range 0 3 --out "$G/a" >/dev/null 2>&1 \
    && ok "the generator writes four seeds" || bad "the generator failed on seeds 0 to 3"
PYTHONDONTWRITEBYTECODE=1 python3 "$GEN" --range 0 3 --out "$G/b" >/dev/null 2>&1
diff -r "$G/a" "$G/b" >/dev/null 2>&1 && ok "one seed gives the same scenario twice" \
    || bad "the generator is not deterministic"
first=$(ls "$G/a" | head -1); second=$(ls "$G/a" | sed -n 2p)
[ -n "$second" ] && ! diff -r "$G/a/$first" "$G/a/$second" >/dev/null 2>&1 \
    && ok "two seeds give two different scenarios" \
    || bad "seed 0 and seed 1 wrote the same scenario"
[ "$(PYTHONDONTWRITEBYTECODE=1 python3 "$GEN" --list --range 0 49 | awk '{print $2}' | sort -u | wc -l)" -eq 50 ] \
    && ok "the first fifty seeds give fifty scenarios" \
    || bad "the first fifty seeds repeat a scenario"
gen_missing=""
for f in track prompt seed.sh check.sh goals; do
    [ -s "$G/a/$first/$f" ] || gen_missing="$gen_missing $f"
done
[ -z "$gen_missing" ] && ok "a generated scenario has every file the lab needs" \
    || bad "a generated scenario is missing:$gen_missing"
bash -n "$G/a/$first/seed.sh" && bash -n "$G/a/$first/check.sh" \
    && ok "its seed.sh and its check.sh parse" || bad "a generated script has a syntax error"
LAB_SCENARIOS="$G/a" bash "$LAB" --dry-run > "$G/dry.log" 2>&1
[ "$(grep -c "$first" "$G/dry.log")" -eq 1 ] && ok "run.sh lists it through LAB_SCENARIOS" \
    || bad "run.sh did not list the generated scenario (see $G/dry.log)"
[ "$(ls "$PLUGIN_ROOT/evals/lab/scenarios" | grep -c '^gen')" -eq 0 ] \
    && ok "no generated scenario sits in the default pass" \
    || bad "a generated scenario is in evals/lab/scenarios, and the release gate would run it"

echo "== a sequence scenario runs one session per change, in one sandbox =="
mkdir -p "$W/scenarios/toy-seq/briefs"
echo behavioral > "$W/scenarios/toy-seq/track"
echo "/hone:run a, and one session per further line of sequence" > "$W/scenarios/toy-seq/prompt"
printf 'a\nb\nc\n' > "$W/scenarios/toy-seq/sequence"
touch "$W/scenarios/toy-seq/by-name"
for c in a b c; do
    printf '# Brief: %s\n\nDo the %s change.\n' "$c" "$c" > "$W/scenarios/toy-seq/briefs/$c.md"
done
# The seed writes no Plan: the driver hands each brief over in turn.
echo "echo 'config/' > .hone-irreversible-paths" > "$W/scenarios/toy-seq/seed.sh"
cat > "$W/scenarios/toy-seq/check.sh" <<'EOF'
unchanged scripts/run-tests.sh
measure steps "$(jq length "$LAB_STEPS")"
measure landed_changes "$(jq '[.[] | select(.landed)] | length' "$LAB_STEPS")/$(jq length "$LAB_STEPS")"
EOF

fresh; rm -f "$W/seq-n"; MODE=seq lab toy-seq >/dev/null; rc=$?
seq_sb=$(echo "$W"/out/*/toy-seq)
[ "$rc" -eq 0 ] && [ "$(result toy-seq .verdict)" = "pass" ] && ok "a sequence run grades as any other" \
    || bad "a sequence run should pass (exit $rc, $(result toy-seq .verdict): $(result toy-seq .reason))"
[ "$(result toy-seq .measures.steps)" = "3" ] && ok "the check reads one record per change" \
    || bad "LAB_STEPS should hold 3 records (got $(result toy-seq -c .measures))"
[ "$(result toy-seq .cost_usd)" = "4.5" ] && ok "the cost is the sum over the three sessions" \
    || bad "the cost of three sessions at 1.5 should be 4.5 (got $(result toy-seq .cost_usd))"
[ "$(result toy-seq .turns)" = "9" ] && ok "the turns are the sum over the sessions" \
    || bad "three sessions of 3 turns should be 9 (got $(result toy-seq .turns))"
[ -s "$seq_sb/step-1/transcript.jsonl" ] && [ -s "$seq_sb/step-3/transcript.jsonl" ] \
    && ok "each session keeps a transcript of its own" || bad "step-1/ and step-3/ should each hold a transcript"
[ "$(jq -s 'length' "$seq_sb/transcript.jsonl")" -gt 9 ] && ok "the joined transcript holds every step" \
    || bad "the joined transcript should hold all three sessions"
[ "$(jq -r '[.[].change] | join(",")' "$seq_sb/steps.json")" = "a,b,c" ] \
    && ok "the steps run in the order of the sequence file" || bad "the steps should run a, b, c"

echo "== a step that lands nothing is human attention, and the sequence goes on =="
[ "$(jq -r '[.[].landed] | join(",")' "$seq_sb/steps.json")" = "true,false,true" ] \
    && ok "the record says which change landed" || bad "step 2 should be the one that did not land"
[ "$(result toy-seq .measures.landed_changes)" = "2/3" ] && ok "a check can count what landed" \
    || bad "landed_changes should be 2/3 (got $(result toy-seq -c .measures))"
seq_log=$(git -C "$seq_sb/repo" log --format=%s 2>&1)
case "$seq_log" in
    *"set the brief for b aside"*) ok "the driver sets the brief of a step that landed nothing aside" ;;
    *) bad "an unlanded brief should be set aside in a commit of its own (log: $(tr '\n' '|' <<<"$seq_log"))" ;;
esac
[ ! -e "$seq_sb/repo/.plans/b.md" ] && ok "no pending Plan is left for the next session" \
    || bad ".plans/b.md should not survive the step that did not land"

echo "== the turn of each step, on both arms =="
[ "$(prompt_sent | head -1)" = "/hone:run c" ] && ok "the full arm sends /hone:run for each change" \
    || bad "the last turn should be /hone:run c (got $(prompt_sent | head -1))"
fresh; rm -f "$W/seq-n"; MODE=seq lab toy-seq --bare >/dev/null
[ "$(result toy-seq .verdict)" != "skipped" ] && ok "a sequence scenario is not skipped on the bare arm" \
    || bad "the bare arm should run a sequence scenario (got $(result toy-seq .reason))"
[ "$(prompt_sent | head -1)" = "# Brief: c" ] && ok "the bare turn of a step is that change's brief" \
    || bad "the bare turn should open with the brief (got $(prompt_sent | head -1))"
prompt_sent | grep -q 'Make the change in this repository' && ok "the bare turn of a step asks for the change" \
    || bad "the bare turn of a step should ask for the change"

echo "== a session that breaks mid-sequence is indeterminate, never a result =="
fresh; rm -f "$W/seq-n"; MODE=seq-dead lab toy-seq >/dev/null; rc=$?
seq_sb=$(echo "$W"/out/*/toy-seq)
[ "$rc" -eq 3 ] && [ "$(result toy-seq .verdict)" = "indeterminate" ] \
    && ok "a step with no result event makes the run indeterminate" \
    || bad "a broken step should be indeterminate (exit $rc, $(result toy-seq .verdict))"
result toy-seq .reason | grep -q 'step 2' && ok "the reason names the step that broke" \
    || bad "the reason should name step 2 (got $(result toy-seq .reason))"
[ "$(jq length "$seq_sb/steps.json")" = "2" ] && ok "the sequence stops at the step that broke" \
    || bad "steps.json should stop after step 2 (got $(jq length "$seq_sb/steps.json"))"

echo "== a sequence scenario stays out of a pass that names none =="
fresh; MODE=land lab --dry-run > "$W/seq-dry.log" 2>&1
grep -q 'toy-seq' "$W/seq-dry.log" && bad "a by-name scenario must not enter a pass that names none" \
    || ok "the dry run lists no sequence scenario of its own accord"

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
