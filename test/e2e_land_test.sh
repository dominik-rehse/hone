#!/bin/bash
# End-to-end proof of the run loop's mechanical spine: a real change flows through
# worktree → test-first build (guard in force) → gate → commit → merge to the
# primary tree → re-verify → worktree removed. The judgment steps (plan-critic,
# consolidate-critic, /code-review) are exercised separately by the evals; this
# pins the deterministic path a landed change takes. Run: bash test/e2e_land_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$PLUGIN_ROOT/hooks/guard.sh"
GATE="$PLUGIN_ROOT/hooks/gate.sh"
WSH="$PLUGIN_ROOT/scripts/worktree.sh"
guard_write() { echo "{\"tool_input\":{\"file_path\":\"$1\"}}" | (cd "$2" && bash "$GUARD"); }
denied() { echo "$1" | grep -q '"permissionDecision":"deny"'; }
step() { printf '  %s\n' "$1"; }
die()  { printf '  FAIL: %s\n' "$1"; exit 1; }

REPO=$(mktemp -d); trap 'rm -rf "$REPO"' EXIT
cd "$REPO" || exit 1
git init -q && git symbolic-ref HEAD refs/heads/main
git config user.email t@t.t; git config user.name t

# A minimal real project: a bash "adapter" running a tiny test file, and the
# hone ephemeral ignores so worktrees/plans don't pollute the tree.
mkdir -p src/mathx scripts
printf '.worktrees/\n.plans/\n' > .gitignore
cat > scripts/run-tests.sh <<'EOF'
#!/bin/bash
# Trivial adapter: source src, assert add(2,3)==5. exit 0=pass.
case "${1:-}" in --all|--unit) shift ;; esac
node -e '
  const {add} = require("./src/mathx/add.js");
  if (add(2,3) !== 5) { console.error("add(2,3) !== 5"); process.exit(1); }
  console.log("ok");
' 2>/dev/null
EOF
chmod +x scripts/run-tests.sh
echo "# seed" > README.md
git add -A && git commit -qm "seed: project skeleton"
command -v node >/dev/null 2>&1 || { echo "  SKIP: node not available"; exit 0; }

echo "== 1. worktree =="
WT=$(bash "$WSH" add mathx-add) || die "worktree add"
[ -d "$WT" ] && step "worktree at ${WT##*/}" || die "worktree missing"

echo "== 2. build: guard enforces test-first =="
# Code before test → denied.
out=$(guard_write "src/mathx/add.js" "$WT")
denied "$out" && step "code-before-test denied" || die "guard should deny code before test"
# Write the failing test (RED artifact) → allowed.
out=$(guard_write "src/mathx/add.test.js" "$WT")
denied "$out" && die "guard should allow the test" || step "test allowed (RED)"
mkdir -p "$WT/src/mathx"
cat > "$WT/src/mathx/add.test.js" <<'EOF'
// behavior: add sums two numbers
const {add} = require("./add.js");
if (add(2,3) !== 5) throw new Error("add broken");
EOF
# Now code is allowed (its test exists).
out=$(guard_write "src/mathx/add.js" "$WT")
denied "$out" && die "guard should allow code once test exists" || step "code allowed once test exists"
cat > "$WT/src/mathx/add.js" <<'EOF'
exports.add = (a, b) => a + b;
EOF

echo "== 3. gate: green in the worktree =="
out=$(cd "$WT" && echo '{}' | bash "$GATE")
echo "$out" | grep -q '"decision":"block"' && die "gate should pass on green suite" || step "gate green"

echo "== 4. commit in the worktree =="
(cd "$WT" && git add -A && git commit -qm "feat(mathx): add()") || die "commit"
step "committed on branch hone/mathx-add"

echo "== 5. land: merge + re-verify + remove, under the lock =="
# `land` does the whole tail: lock → merge --no-ff → run-tests.sh --all → remove.
bash "$WSH" land mathx-add >/dev/null 2>&1 || die "land failed on a green change"
git log --oneline -1 | grep -q "Merge branch 'hone/mathx-add'" || die "merge commit not on the primary tree"
bash scripts/run-tests.sh >/dev/null 2>&1 || die "suite red in primary after land"
[ -d "$WT" ] && die "worktree still present after land" || step "landed, verified, and worktree removed"
git show-ref --verify --quiet refs/heads/hone/mathx-add && die "merged branch should be deleted at land" || step "merged branch hone/mathx-add deleted"

echo "== 5b. land rolls back a regression, leaving the trunk green =="
# A change that passes on its own branch but breaks the suite once merged. `land`
# must merge, see red, roll the merge back, and keep the worktree as evidence.
WT_R=$(bash "$WSH" add mathx-regress) || die "worktree add mathx-regress"
# Its test asserts a NEW contract (mul), but it also rewrites add() to break the
# already-landed add test — so the branch is green alone, red after merge.
cat > "$WT_R/src/mathx/mul.test.js" <<'EOF'
const {mul} = require("./mul.js");
if (mul(2,3) !== 6) throw new Error("mul broken");
EOF
cat > "$WT_R/src/mathx/mul.js" <<'EOF'
exports.mul = (a, b) => a * b;
EOF
cat > "$WT_R/src/mathx/add.js" <<'EOF'
exports.add = (a, b) => a + b + 1;
EOF
# Broaden the adapter to run BOTH test files so --all catches the regression.
cat > "$WT_R/scripts/run-tests.sh" <<'EOF'
#!/bin/bash
case "${1:-}" in --all|--unit) shift ;; esac
node -e '
  const {add} = require("./src/mathx/add.js");
  const {mul} = require("./src/mathx/mul.js");
  if (add(2,3) !== 5) { console.error("add regressed"); process.exit(1); }
  if (mul(2,3) !== 6) { console.error("mul broken"); process.exit(1); }
' 2>/dev/null
EOF
(cd "$WT_R" && git add -A && git commit -qm "feat(mathx): mul() [breaks add]")
PRE=$(git rev-parse HEAD)
bash "$WSH" land mathx-regress >/dev/null 2>&1; rc=$?
[ "$rc" -eq 6 ] || die "land should exit 6 on a post-merge regression (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "regressing merge should be rolled back — HEAD moved"
bash scripts/run-tests.sh >/dev/null 2>&1 || die "trunk left red after a rolled-back land"
git show-ref --verify --quiet refs/heads/hone/mathx-regress || die "branch should survive a failed land as evidence"
[ -d "$WT_R" ] || die "worktree should survive a failed land as evidence"
step "regression merged, rolled back, trunk green, evidence kept"
bash "$WSH" remove "$WT_R" >/dev/null 2>&1; git branch -D hone/mathx-regress >/dev/null 2>&1

echo "== 5c. land serializes: a held lock makes a concurrent land wait =="
if command -v flock >/dev/null 2>&1; then
  LOCK="$(git rev-parse --git-common-dir)/hone-land.lock"
  ( flock 8; sleep 3; ) 8>"$LOCK" &   # hold the land lock ~3s
  HOLDER=$!
  sleep 0.3                            # let the holder acquire it first
  # A land with a 1s wait must give up (exit 5) while the lock is held, instead
  # of interleaving its merge with the holder's critical section.
  HONE_LAND_LOCK_TIMEOUT=1 bash "$WSH" land whatever >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 5 ] || die "land under a held lock should time out with exit 5 (got $rc)"
  wait "$HOLDER" 2>/dev/null
  step "concurrent land waited on the lock, then timed out (exit 5)"
else
  step "SKIP lock test: flock not available"
fi

echo "== 5d. verify + gate --all share the suite lock =="
if command -v flock >/dev/null 2>&1; then
  LOCK="$(git rev-parse --git-common-dir)/hone-land.lock"
  # verify is the sanctioned manual full-suite run: green here, serialized below.
  bash "$WSH" verify >/dev/null 2>&1 || die "verify should run the suite green"
  step "verify runs the full suite (green)"
  ( flock 8; sleep 3; ) 8>"$LOCK" &   # hold the suite lock ~3s
  HOLDER=$!
  sleep 0.3
  HONE_LAND_LOCK_TIMEOUT=1 bash "$WSH" verify >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 5 ] || die "verify under a held lock should time out with exit 5 (got $rc)"
  wait "$HOLDER" 2>/dev/null
  step "concurrent verify waited on the lock, then timed out (exit 5)"
  # The gate's --all tier (clean hone/* branch, the pre-land moment) takes the
  # same lock: while another suite is live it blocks the stop instead of
  # running red under contention.
  WT_G=$(bash "$WSH" add gate-lock) || die "worktree add gate-lock"
  ( cd "$WT_G" && git commit -q --allow-empty -m "wip: pre-land" ) || die "commit in gate-lock"
  ( flock 8; sleep 3; ) 8>"$LOCK" &
  HOLDER=$!
  sleep 0.3
  out=$(cd "$WT_G" && echo '{}' | HONE_SUITE_LOCK_TIMEOUT=1 bash "$GATE")
  echo "$out" | grep -q '"decision":"block"' || die "gate --all under a held suite lock should block the stop"
  echo "$out" | grep -q "another session is running the full suite" || die "gate block should name the live suite as the reason"
  wait "$HOLDER" 2>/dev/null
  # Lock free again → the gate runs --all and passes green.
  out=$(cd "$WT_G" && echo '{}' | bash "$GATE")
  echo "$out" | grep -q '"decision":"block"' && die "gate should pass once the suite lock is free"
  step "gate --all blocks while a suite is live, passes when the lock frees"
  bash "$WSH" remove "$WT_G" >/dev/null 2>&1; git branch -D hone/gate-lock >/dev/null 2>&1
else
  step "SKIP suite-lock tests: flock not available"
fi

echo "== 5e. authority gate (on by default): consequential changes need a grant =="
# (a) A reversible change lands freely — the gate only bites consequential diffs.
WT_OK=$(bash "$WSH" add rev-change) || die "worktree add rev-change"
echo "// harmless" > "$WT_OK/src/mathx/notes.js"
(cd "$WT_OK" && git add -A && git commit -qm "chore(mathx): a reversible note")
bash "$WSH" land rev-change >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a reversible change should land freely (got $rc)"
step "reversible change lands without a grant"
# (b) A consequential change (destructive SQL in a migration) is refused BEFORE the
# merge — by default, no marker needed.
WT_C=$(bash "$WSH" add db-drop) || die "worktree add db-drop"
mkdir -p "$WT_C/db/migrations"
echo "DROP TABLE legacy_sessions;" > "$WT_C/db/migrations/0002_drop.sql"
(cd "$WT_C" && git add -A && git commit -qm "feat(db): drop legacy_sessions")
PRE=$(git rev-parse HEAD)
bash "$WSH" land db-drop >/dev/null 2>&1; rc=$?
[ "$rc" -eq 8 ] || die "consequential land without a grant should exit 8 by default (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "ungranted consequential change must not touch the trunk"
[ -d "$WT_C" ] || die "worktree should survive an ungranted consequential land as evidence"
step "consequential change without a grant refused by default (exit 8), trunk untouched"
# (c) With a scoped grant, it lands and the authorization is recorded in history.
mkdir -p "$REPO/.hone-grant"
echo "approved by t@t.t: legacy_sessions is unused" > "$REPO/.hone-grant/db-drop"
bash "$WSH" land db-drop >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "granted consequential land should succeed (got $rc)"
git log --format=%B -1 | grep -q "legacy_sessions is unused" || die "grant text should be recorded in the merge commit body"
step "granted consequential change landed, authorization recorded in history"
# (d) .hone-authority-off disables the gate — the same change lands unattended.
touch "$REPO/.hone-authority-off"; rm -f "$REPO/.hone-grant/db-drop"
WT_C2=$(bash "$WSH" add db-drop2) || die "worktree add db-drop2"
mkdir -p "$WT_C2/db/migrations"
echo "DROP TABLE more_legacy;" > "$WT_C2/db/migrations/0003_drop.sql"
(cd "$WT_C2" && git add -A && git commit -qm "feat(db): drop more_legacy")
bash "$WSH" land db-drop2 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "consequential change should land freely when .hone-authority-off is set (got $rc)"
step "with .hone-authority-off, a consequential change lands unattended"
rm -f "$REPO/.hone-authority-off"

echo "== 5f. proof gate (on by default): real-environment changes need a discharge =="
# (a) An assertion-class change (no Proof: trailer) is never gated.
WT_A2=$(bash "$WSH" add assert-change) || die "worktree add assert-change"
echo "// assertion-class" > "$WT_A2/src/mathx/plain.js"
(cd "$WT_A2" && git add -A && git commit -qm "chore(mathx): assertion-class change")
bash "$WSH" land assert-change >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "an assertion-class change should land (got $rc)"
step "assertion-class change lands (no Proof: trailer, not gated)"
# (b) A real-environment change with no discharge is refused before the merge — by default.
WT_P=$(bash "$WSH" add ui-flow) || die "worktree add ui-flow"
echo "// browser flow" > "$WT_P/src/mathx/flow.js"
(cd "$WT_P" && git add -A && git commit -qm "feat(mathx): checkout flow

Proof: real-environment")
PRE=$(git rev-parse HEAD)
bash "$WSH" land ui-flow >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] || die "an undischarged real-environment change should exit 7 by default (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "an unproven real-environment change must not touch the trunk"
step "real-environment change without a discharge refused by default (exit 7), trunk untouched"
# (c) A human attestation discharges it and it lands.
mkdir -p "$REPO/.hone-proof"
echo "ran the browser journey against staging 2026-07-24 — ok" > "$REPO/.hone-proof/ui-flow"
bash "$WSH" land ui-flow >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "an attested real-environment change should land (got $rc)"
step "attested real-environment change landed"
rm -f "$REPO/.hone-proof/ui-flow"
# (d) A green scripts/proof.sh also discharges it.
WT_P2=$(bash "$WSH" add ui-flow2) || die "worktree add ui-flow2"
echo "// second flow" > "$WT_P2/src/mathx/flow2.js"
(cd "$WT_P2" && git add -A && git commit -qm "feat(mathx): second flow

Proof: real-environment")
printf '#!/bin/bash\nexit 0\n' > "$REPO/scripts/proof.sh"   # a real-env check that passes
bash "$WSH" land ui-flow2 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a green scripts/proof.sh should discharge the proof (got $rc)"
step "real-environment change discharged by a green scripts/proof.sh"
# (e) A red scripts/proof.sh keeps it out (exit 7).
rm -f "$REPO/scripts/proof.sh"
WT_P3=$(bash "$WSH" add ui-flow3) || die "worktree add ui-flow3"
echo "// third flow" > "$WT_P3/src/mathx/flow3.js"
(cd "$WT_P3" && git add -A && git commit -qm "feat(mathx): third flow

Proof: real-environment")
printf '#!/bin/bash\nexit 1\n' > "$REPO/scripts/proof.sh"   # a real-env check that fails
PRE=$(git rev-parse HEAD)
bash "$WSH" land ui-flow3 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] || die "a red scripts/proof.sh should keep a real-environment change out (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "a failed proof must not touch the trunk"
step "real-environment change with a red scripts/proof.sh refused (exit 7)"
# (f) .hone-proof-off disables the gate — the same undischarged change lands.
rm -f "$REPO/scripts/proof.sh"; touch "$REPO/.hone-proof-off"
bash "$WSH" land ui-flow3 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a real-environment change should land when .hone-proof-off is set (got $rc)"
step "with .hone-proof-off, an undischarged real-environment change lands"
rm -f "$REPO/.hone-proof-off"

echo "== 7. add from inside a sibling worktree: anchors to the main tree =="
# An orchestrator's cwd drifts into change A's worktree before starting change B.
# `add B` must land at <main_root>/.worktrees/B (not nested under A) and branch
# off the primary HEAD (not A's unlanded commit).
WT_A=$(bash "$WSH" add sib-a) || die "worktree add sib-a"
( cd "$WT_A" && git commit -q --allow-empty -m "wip: A only, unlanded" ) || die "commit in A"
WT_B=$(cd "$WT_A" && bash "$WSH" add sib-b) || die "worktree add sib-b from inside A"
[ "$WT_B" = "$REPO/.worktrees/sib-b" ] || die "sib-b nested/misplaced: $WT_B"
step "sib-b at main tree, not nested under A"
base=$(git merge-base main hone/sib-b)
[ "$base" = "$(git rev-parse main)" ] || die "sib-b based off A's HEAD, not primary"
step "sib-b branched off the primary, not A's unlanded HEAD"
bash "$WSH" remove "$WT_B" >/dev/null 2>&1; bash "$WSH" remove "$WT_A" >/dev/null 2>&1

echo
echo "e2e land path: PASS"
