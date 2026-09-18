#!/bin/bash
# Mechanical proof of evals/candidate.sh, the procedure that judges a candidate
# change to hone (docs/roadmap.md). A scratch repository plays hone, and
# hand-written result files play the two arms, so this test makes no model
# call. Run: bash test/candidate_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
CANDIDATE="$PLUGIN_ROOT/evals/candidate.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
R="$W/hone"
mkdir -p "$R"/{agents,hooks,skills/run,skills/plan,templates,scripts,docs,test} "$R"/evals/lab/scenarios/{seeded-prose,seeded-structure,happy-path}
printf 'one two three four five six\n' > "$R/agents/consolidate-critic.md"
printf 'the loop\n' > "$R/skills/run/SKILL.md"
printf 'the plan skill\n' > "$R/skills/plan/SKILL.md"
printf 'echo guard\n' > "$R/hooks/guard.sh"
printf 'echo adapter\n' > "$R/templates/node.sh"
printf 'echo setup\n' > "$R/scripts/setup.sh"
printf '# Upgrading\n' > "$R/docs/upgrading.md"
printf 'exit "$(cat "$(dirname "$0")/rc")"\n' > "$R/test/run.sh"; echo 0 > "$R/test/rc"
for s in seeded-prose seeded-structure happy-path; do echo landed > "$R/evals/lab/scenarios/$s/check.sh"; done
echo "tidy yes" > "$R/evals/lab/scenarios/seeded-prose/goals"
printf '%s\n' "# floors" "consolidate-critic claude-floor-1" "lab claude-floor-1 claude-below-1" > "$R/evals/floors"
git -C "$R" init -q -b main
git -C "$R" -c user.name=t -c user.email=t@example.invalid add -A
git -C "$R" -c user.name=t -c user.email=t@example.invalid commit -qm "chore: base"

candidate() { CANDIDATE_ROOT="$R" bash "$CANDIDATE" "$@" 2>&1; }
reset_tree() { git -C "$R" checkout -q -- . && git -C "$R" clean -qfd; echo 0 > "$R/test/rc"; rm -rf "$W/runs" "$W"/*.jsonl; }

# lab_run ARM N SCENARIO VERDICT TIDY [ENDING] [MODEL]: one result.json.
lab_run() {
    local plugin; [ "$1" = base ] && plugin=aaa || plugin=bbb
    mkdir -p "$W/runs/$1-$2/$3"
    jq -n --arg s "$3" --arg v "$4" --arg tidy "$5" --arg e "${6:-landed hone/x feat src}" --arg m "${7:-claude-floor-1}" --arg p "${PLUGIN:-$plugin}" \
        '{scenario: $s, verdict: $v, reason: "a check failed", model: $m, plugin: $p, ending: $e, cost_usd: 2, nested_cost_usd: 0.5,
          judge_cost_usd: 0, seconds: 600, measures: (if $tidy == "" then {} else {tidy: $tidy} end)}' > "$W/runs/$1-$2/$3/result.json"
}
# The two seeded scenarios, three runs per arm. $1 and $2 are the tidy values
# of the three baseline and the three candidate runs of seeded-prose.
lab_arms() {
    local i v arm values
    rm -rf "$W/runs"
    for arm in base cand; do
        values="$1"; [ "$arm" = cand ] && values="$2"
        i=0; for v in $values; do i=$((i+1)); lab_run "$arm" "$i" seeded-prose pass "$v"; lab_run "$arm" "$i" seeded-structure pass ""; done
    done
}
dirs() { local d; d=$(printf '%s,' "$W"/runs/"$1"-*); echo "${d%,}"; }
# unit ARM RIGHT TOTAL [TARGET]: one case with RIGHT correct votes of TOTAL.
unit() {
    local i token pass=true
    [ $(( $2 * 2 )) -gt "$3" ] || pass=false
    for i in $(seq 1 "$3"); do
        [ "$i" -le "$2" ] && token=CLEAN || token=CUTS
        jq -cn --arg t "${4:-consolidate-critic}" --arg token "$token" --argjson i "$i" --argjson pass "$pass" \
            '{target: $t, case: "helper", vote: $i, model: "claude-floor-1", expected: "CLEAN", token: $token,
              verdict: (if $pass then "CLEAN" else "CUTS" end), pass: $pass, cost_usd: 0.05}'
    done > "$W/$1.jsonl"
}
decide() { candidate decide --base "$(dirs base)" --cand "$(dirs cand)" --unit-base "$W/base.jsonl" --unit-cand "$W/cand.jsonl"; }

echo "== plan reads the diff: the suites owed, the upgrade path, the size =="
echo "one two three" > "$R/agents/consolidate-critic.md"
out=$(candidate plan); rc=$?
[ "$rc" -eq 0 ] && ok "plan exits 0" || bad "plan should exit 0 (got $rc: $out)"
grep -q 'evals/run.sh consolidate-critic' <<<"$out" && grep -q 'seeded-prose, 3 runs per arm' <<<"$out" \
    && ok "a critic edit owes its unit target and the seeded scenarios" || bad "the plan should name the unit target and the seeded scenarios: $out"
grep -q 'upgrade path: none-needed' <<<"$out" && ok "a prompt edit needs no upgrade path" || bad "upgrade path should be none-needed: $out"
grep -q 'size: prose 11 words at HEAD and 8 in the tree, code 6 and 6' <<<"$out" && ok "the size counts the shipped words of both sides" || bad "the size line is wrong: $out"

echo "== a cut that holds every measure is accepted =="
lab_arms "yes yes yes" "yes yes yes"; unit base 3 3; unit cand 3 3
out=$(decide); rc=$?
[ "$rc" -eq 0 ] && grep -q 'verdict: accept' <<<"$out" && ok "equal outcomes and a smaller plugin give accept" || bad "should accept (got $rc: $out)"
grep -q 'PRICE lab: over 2 scenario(s)' <<<"$out" && ok "the price of both arms is printed" || bad "the price line is missing: $out"

echo "== a constraint that breaks rejects =="
unit cand 1 3
out=$(decide); rc=$?
[ "$rc" -eq 1 ] && grep -q 'REJECT unit consolidate-critic/helper' <<<"$out" && ok "a flipped plurality rejects" || bad "a flip should reject (got $rc: $out)"
# An arm may have several --json files. A flip in any of them rejects,
# whichever file comes first.
unit cand 3 3; cp "$W/cand.jsonl" "$W/cand-first.jsonl"; unit cand 1 3
out=$(candidate decide --base "$(dirs base)" --cand "$(dirs cand)" --unit-base "$W/base.jsonl" --unit-cand "$W/cand-first.jsonl,$W/cand.jsonl"); rc=$?
[ "$rc" -eq 1 ] && grep -q 'REJECT unit consolidate-critic/helper: the candidate answers CUTS' <<<"$out" && ok "a flip in the second file of an arm rejects too" || bad "a flip in a later file should reject (got $rc: $out)"
rm -f "$W/cand-first.jsonl"
unit cand 3 3; lab_run cand 2 seeded-structure fail ""
out=$(decide); rc=$?
[ "$rc" -eq 1 ] && grep -q 'REJECT lab seeded-structure: 1 of 3' <<<"$out" && ok "a failed lab run rejects" || bad "a lab fail should reject (got $rc: $out)"
lab_run cand 2 seeded-structure indeterminate ""
out=$(decide); rc=$?
[ "$rc" -eq 3 ] && grep -q 'indeterminate. Run them again' <<<"$out" && ok "an indeterminate run is undecided, never a result" || bad "indeterminate should give undecided (got $rc: $out)"
lab_run cand 2 seeded-structure pass ""

echo "== a tally that moves without a flip is decided at ten votes =="
unit cand 2 3
out=$(decide); rc=$?
[ "$rc" -eq 3 ] && grep -q 'Run this case at --votes 10' <<<"$out" && ok "2/3 after 3/3 is undecided and names the run to make" || bad "a moved tally should be undecided (got $rc: $out)"
unit base 10 10; unit cand 9 10
out=$(decide); rc=$?
[ "$rc" -eq 0 ] && grep -q 'inside the noise' <<<"$out" && ok "one vote of ten is noise" || bad "9/10 after 10/10 should accept (got $rc: $out)"
unit cand 8 10
out=$(decide); rc=$?
[ "$rc" -eq 1 ] && grep -q 'the tally fell from 10/10 to 8/10' <<<"$out" && ok "two votes of ten reject" || bad "8/10 after 10/10 should reject (got $rc: $out)"
unit base 3 3; unit cand 3 3

echo "== an outcome measure needs three runs per arm, and two runs move it =="
lab_arms "yes yes yes" "yes no no"
out=$(decide); rc=$?
[ "$rc" -eq 1 ] && grep -q 'the outcome tidy=yes dropped from 3/3 runs to 1/3' <<<"$out" && ok "an outcome that drops by two runs rejects" || bad "a dropped outcome should reject (got $rc: $out)"
lab_arms "yes yes yes" "yes yes no"
out=$(decide); rc=$?
[ "$rc" -eq 0 ] && grep -q 'NOTE lab seeded-prose: tidy=yes in 3/3 baseline and 2/3' <<<"$out" && ok "one run is noise" || bad "one run of three should not reject (got $rc: $out)"
rm -rf "$W/runs/cand-3"
out=$(decide); rc=$?
[ "$rc" -eq 3 ] && grep -q 'needs 3 per arm' <<<"$out" && ok "two candidate runs of a measure are undecided" || bad "a thin arm should be undecided (got $rc: $out)"

echo "== an addition must show its gain =="
reset_tree
echo "one two three four five six seven eight nine" > "$R/agents/consolidate-critic.md"
lab_arms "no no no" "no no yes"; unit base 3 3; unit cand 3 3
out=$(decide); rc=$?
[ "$rc" -eq 1 ] && grep -q 'REJECT size: the candidate grows the shipped prose by 3 words' <<<"$out" && ok "growth with no gain rejects" || bad "an addition with no gain should reject (got $rc: $out)"
lab_arms "no no no" "yes no yes"
out=$(decide); rc=$?
[ "$rc" -eq 0 ] && grep -q 'GAIN lab seeded-prose: the outcome tidy=yes rose from 0/3 runs to 2/3' <<<"$out" && ok "growth with a gain of two runs is accepted" || bad "an addition with a gain should accept (got $rc: $out)"

echo "== a deterministic check may grow the code with no gain =="
reset_tree
echo "echo guard and one more exact check" > "$R/hooks/guard.sh"
lab_arms "yes yes yes" "yes yes yes"
for i in 1 2 3; do lab_run base "$i" happy-path pass ""; lab_run cand "$i" happy-path pass ""; done
out=$(candidate decide --base "$(dirs base)" --cand "$(dirs cand)"); rc=$?
[ "$rc" -eq 0 ] && grep -q 'The shipped code has 11, and it had 6 (5)' <<<"$out" && ok "a hook that grows is accepted when every constraint holds" || bad "code growth should need no gain (got $rc: $out)"

echo "== predictable: more endings than the baseline rejects =="
reset_tree
echo "one two three" > "$R/agents/consolidate-critic.md"
unit base 3 3; unit cand 3 3
lab_arms "yes yes yes" "yes yes yes"
lab_run cand 1 seeded-structure pass "" "stopped worktrees=1"; lab_run cand 2 seeded-structure pass "" "landed hone/y fix src"
out=$(decide); rc=$?
[ "$rc" -eq 1 ] && grep -q 'ended 3 ways' <<<"$out" && ok "three endings after one reject" || bad "a less predictable candidate should reject (got $rc: $out)"

echo "== the arms must be two plugins, measured on the floor =="
lab_arms "yes yes yes" "yes yes yes"
PLUGIN=aaa lab_run cand 1 seeded-structure pass ""
out=$(decide); rc=$?
[ "$rc" -eq 3 ] && grep -q 'the candidate runs measured 2 different plugins' <<<"$out" && ok "a mixed arm is undecided" || bad "a mixed arm should be undecided (got $rc: $out)"
lab_arms "yes yes yes" "yes yes yes"
lab_run cand 1 seeded-structure pass "" "landed hone/x feat src" claude-better-9
out=$(decide); rc=$?
[ "$rc" -eq 3 ] && grep -q 'a run used claude-better-9, and evals/floors allows' <<<"$out" && ok "a run above the floor is undecided" || bad "a run off the floor should be undecided (got $rc: $out)"
lab_arms "yes yes yes" "yes yes yes"
lab_run cand 1 seeded-structure pass "" "landed hone/x feat src" claude-below-1
out=$(decide); rc=$?
[ "$rc" -eq 3 ] && grep -q 'lab seeded-structure: the two arms ran on different models' <<<"$out" && ok "two arms on two models are undecided" || bad "arms on different models should be undecided (got $rc: $out)"
for i in 1 2 3; do for arm in base cand; do lab_run "$arm" "$i" seeded-structure pass "" "landed hone/x feat src" claude-below-1; done; done
out=$(decide); rc=$?
[ "$rc" -eq 0 ] && ok "both arms on a listed model below the floor are accepted" || bad "a listed model on both arms should accept (got $rc: $out)"

echo "== a run directory with no result says so =="
mkdir -p "$W/empty-run/seeded-prose"
out=$(candidate decide --base "$(dirs base)" --cand "$W/empty-run"); rc=$?
[ "$rc" -eq 2 ] && grep -q "no result.json below $W/empty-run" <<<"$out" && ok "an empty run directory exits 2 and names itself" || bad "an empty run directory should exit 2 with a message (got $rc: $out)"
echo "not json" > "$W/broken.jsonl"
out=$(candidate decide --unit-cand "$W/broken.jsonl"); rc=$?
[ "$rc" -eq 2 ] && grep -q "cannot read $W/broken.jsonl" <<<"$out" && ok "a malformed --json file exits 2 and names itself" || bad "a malformed file should exit 2 with a message (got $rc: $out)"
rm -rf "$W/empty-run" "$W/broken.jsonl"

echo "== the size counts what git would commit =="
echo "scratch scratch scratch scratch scratch scratch scratch scratch" > "$R/agents/scratch.md"
echo "agents/scratch.md" > "$R/.git/info/exclude"
out=$(candidate plan)
grep -q 'prose 11 words at HEAD and 8 in the tree' <<<"$out" && ok "an ignored file in a shipped directory does not read as growth" || bad "an ignored file should not count: $out"
rm -f "$R/agents/scratch.md"; : > "$R/.git/info/exclude"

echo "== an owed suite with no result is undecided =="
lab_arms "yes yes yes" "yes yes yes"
out=$(candidate decide --base "$(dirs base)" --cand "$(dirs cand)"); rc=$?
[ "$rc" -eq 3 ] && grep -q 'owes this target, and --unit-cand has no record' <<<"$out" && ok "a missing unit target is named" || bad "a missing unit target should be undecided (got $rc: $out)"
reset_tree
echo "echo guard, shorter" > "$R/hooks/guard.sh"; echo "x" > "$R/hooks/guard.sh"
lab_arms "yes yes yes" "yes yes yes"
out=$(candidate decide --base "$(dirs base)" --cand "$(dirs cand)"); rc=$?
[ "$rc" -eq 3 ] && grep -q 'owes the whole lab, and --cand has no run of this scenario' <<<"$out" && grep -q 'lab happy-path' <<<"$out" \
    && ok "a hook change owes every scenario" || bad "a hook change should owe the whole lab (got $rc: $out)"
grep -q 'NOTE mechanical: test/run.sh is green' <<<"$out" && ok "a hook change runs the mechanical suite" || bad "the mechanical suite should have run: $out"
echo 1 > "$R/test/rc"
out=$(candidate decide --base "$(dirs base)" --cand "$(dirs cand)"); rc=$?
[ "$rc" -eq 1 ] && grep -q 'REJECT mechanical' <<<"$out" && ok "a red mechanical suite rejects" || bad "a red mechanical suite should reject (got $rc: $out)"

echo "== the upgrade path is part of the candidate =="
reset_tree
echo "x" > "$R/templates/node.sh"
out=$(candidate decide); rc=$?
[ "$rc" -eq 1 ] && grep -q 'REJECT upgrade' <<<"$out" && ok "a template change with no path rejects" || bad "a missing upgrade path should reject (got $rc: $out)"
echo "- 9.9.9: copy the new adapter by hand" >> "$R/docs/upgrading.md"
out=$(candidate decide); rc=$?
[ "$rc" -eq 0 ] && grep -q 'PRICE upgrade: a person must act' <<<"$out" && ok "a manual path is accepted, and it shows in the price" || bad "a manual path should accept with a price line (got $rc: $out)"
reset_tree
echo "x" > "$R/skills/run/SKILL.md"
out=$(candidate plan --state-change)
grep -q 'upgrade path: missing' <<<"$out" && ok "--state-change declares a change that the paths do not show" || bad "--state-change should demand a path: $out"

echo "== a path that no suite measures is undecided =="
reset_tree
echo "x" > "$R/skills/plan/SKILL.md"
out=$(candidate decide); rc=$?
[ "$rc" -eq 3 ] && grep -q 'no suite measures skills/plan/SKILL.md' <<<"$out" && ok "the plan skill has no suite, and the verdict says so" || bad "an unmeasured path should be undecided (got $rc: $out)"

candidate bogus >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown mode exits 2" || bad "an unknown mode should exit 2 (got $rc)"

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
