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
out=$(bash "$WSH" land mathx-add 2>/dev/null) || die "land failed on a green change"
git log --oneline -1 | grep -q "Merge branch 'hone/mathx-add'" || die "merge commit not on the primary tree"
bash scripts/run-tests.sh >/dev/null 2>&1 || die "suite red in primary after land"
[ -d "$WT" ] && die "worktree still present after land" || step "landed, verified, and worktree removed"
git show-ref --verify --quiet refs/heads/hone/mathx-add && die "merged branch should be deleted at land" || step "merged branch hone/mathx-add deleted"
# A silent success made the caller re-derive the outcome from `git log`, so a
# green land says what it did: the merge commit, the green suite, the cleanup.
echo "$out" | grep -q "landed hone/mathx-add as merge commit" || die "land should print a success receipt"
echo "$out" | grep -qF "$(git rev-parse --short HEAD)" || die "the receipt should name the merge commit"
echo "$out" | grep -q "post-merge suite" || die "the receipt should report the post-merge suite"
echo "$out" | grep -q "removed the worktree" || die "the receipt should report the cleanup"
echo "$out" | grep -q "changed a lockfile" && die "a change with no lockfile should draw no reinstall notice"
step "the receipt names the merge commit, the green suite, and the cleanup"

echo "== 5a. land names a landed lockfile =="
# A merged lockfile leaves the primary tree's install behind the manifest, and
# nothing reinstalls it. Every ecosystem's lockfile counts, at any depth.
WT_L=$(bash "$WSH" add lock-bump) || die "worktree add lock-bump"
printf '{"lockfileVersion":1}\n' > "$WT_L/bun.lock"
mkdir -p "$WT_L/packages/api"
printf 'version = 1\n' > "$WT_L/packages/api/uv.lock"
printf '// unrelated\n' > "$WT_L/src/mathx/dep.js"
(cd "$WT_L" && git add -A && git commit -qm "chore(deps): bump the lockfiles")
out=$(bash "$WSH" land lock-bump 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] || die "a lockfile change should land (got $rc)"
echo "$out" | grep -q "changed a lockfile" || die "land should name the lockfile change"
echo "$out" | grep -q "reinstall dependencies" || die "the notice should name the reinstall step"
echo "$out" | grep -qx "  bun.lock" || die "the notice should name the root lockfile"
echo "$out" | grep -qx "  packages/api/uv.lock" || die "the notice should name a nested lockfile"
echo "$out" | grep -q "src/mathx/dep.js" && die "the notice should list lockfiles only"
step "a landed lockfile draws a reinstall notice naming every lockfile"

echo "== 5b. land rolls back a regression, leaving the trunk green =="
# A change that passes on its own branch but breaks the suite once merged. `land`
# must merge, see red, roll the merge back, and keep the worktree as evidence.
WT_R=$(bash "$WSH" add mathx-regress) || die "worktree add mathx-regress"
# Its test asserts a NEW contract (mul), but it also rewrites add() to break the
# already-landed add test, so the branch is green alone, red after merge.
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
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "regressing merge should be rolled back; HEAD moved"
bash scripts/run-tests.sh >/dev/null 2>&1 || die "trunk left red after a rolled-back land"
git show-ref --verify --quiet refs/heads/hone/mathx-regress || die "branch should survive a failed land as evidence"
[ -d "$WT_R" ] || die "worktree should survive a failed land as evidence"
step "regression merged, rolled back, trunk green, evidence kept"
bash "$WSH" remove "$WT_R" >/dev/null 2>&1; git branch -D hone/mathx-regress >/dev/null 2>&1

echo "== 5b2. land re-runs the optional adapters and rolls back a red one =="
# The gate keeps every worktree lint-green, but a merge result is a third tree:
# two lint-green parents can merge lint-red. land must run the same optional
# adapters the gate runs, and give a red one the suite's rollback.
cat > scripts/lint.sh <<'EOF'
#!/bin/bash
! grep -rq "LINT-RED" src
EOF
git add scripts/lint.sh && git commit -qm "chore: add a lint adapter"
WT_LR=$(bash "$WSH" add lint-red) || die "worktree add lint-red"
echo "// LINT-RED" > "$WT_LR/src/mathx/styled.js"
(cd "$WT_LR" && git add -A && git commit -qm "feat(mathx): a change lint rejects")
PRE=$(git rev-parse HEAD)
out=$(bash "$WSH" land lint-red 2>&1); rc=$?
[ "$rc" -eq 6 ] || die "land should exit 6 on post-merge lint red (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "lint-red merge should be rolled back; HEAD moved"
echo "$out" | grep -q "lint failed in the primary tree" || die "the refusal should name the failing adapter"
echo "$out" | grep -q "hone-land.log" || die "the refusal should name the land log"
[ -d "$WT_LR" ] || die "worktree should survive a lint-red land as evidence"
git show-ref --verify --quiet refs/heads/hone/lint-red || die "branch should survive a lint-red land as evidence"
bash scripts/lint.sh >/dev/null 2>&1 || die "trunk left lint-red after a rolled-back land"
step "lint-red merge rolled back (exit 6), trunk lint-green, evidence kept"
# Fixed in the same worktree, the change lands, so a green adapter never blocks.
echo "// styled" > "$WT_LR/src/mathx/styled.js"
(cd "$WT_LR" && git add -A && git commit -qm "fix(mathx): satisfy lint")
bash "$WSH" land lint-red >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a lint-green change should land (got $rc)"
step "the fixed change lands under the same adapter"
# A red typecheck adapter gets the identical treatment, named as itself.
printf '#!/bin/bash\nexit 1\n' > scripts/typecheck.sh
git add scripts/typecheck.sh && git commit -qm "chore: add a failing typecheck adapter"
WT_TC=$(bash "$WSH" add type-red) || die "worktree add type-red"
echo "// typed" > "$WT_TC/src/mathx/typed.js"
(cd "$WT_TC" && git add -A && git commit -qm "feat(mathx): a change under red typecheck")
PRE=$(git rev-parse HEAD)
out=$(bash "$WSH" land type-red 2>&1); rc=$?
[ "$rc" -eq 6 ] || die "land should exit 6 on post-merge typecheck red (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "typecheck-red merge should be rolled back; HEAD moved"
echo "$out" | grep -q "typecheck failed in the primary tree" || die "the refusal should name typecheck"
git rm -q scripts/typecheck.sh && git commit -qm "chore: drop the typecheck adapter"
bash "$WSH" remove "$WT_TC" >/dev/null 2>&1; git branch -D hone/type-red >/dev/null 2>&1
step "typecheck-red merge rolled back (exit 6), named as typecheck"

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

echo "== 5e. authority gate: irreversible changes need a grant =="
# (a) A reversible change lands freely. The gate only bites irreversible diffs.
WT_OK=$(bash "$WSH" add rev-change) || die "worktree add rev-change"
echo "// harmless" > "$WT_OK/src/mathx/notes.js"
(cd "$WT_OK" && git add -A && git commit -qm "chore(mathx): a reversible note")
bash "$WSH" land rev-change >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a reversible change should land freely (got $rc)"
step "reversible change lands without a grant"
# (b) An irreversible change (destructive SQL in a migration) is refused BEFORE
# the merge. No marker needed.
WT_C=$(bash "$WSH" add db-drop) || die "worktree add db-drop"
mkdir -p "$WT_C/db/migrations"
echo "DROP TABLE legacy_sessions;" > "$WT_C/db/migrations/0002_drop.sql"
(cd "$WT_C" && git add -A && git commit -qm "feat(db): drop legacy_sessions")
PRE=$(git rev-parse HEAD)
bash "$WSH" land db-drop >/dev/null 2>&1; rc=$?
[ "$rc" -eq 8 ] || die "irreversible land without a grant should exit 8 (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "ungranted irreversible change must not touch the trunk"
[ -d "$WT_C" ] || die "worktree should survive an ungranted irreversible land as evidence"
step "irreversible change without a grant refused (exit 8), trunk untouched"
# (b2) An empty grant authorizes nothing and leaves no audit trail: still 8.
mkdir -p "$REPO/.hone-grant" && : > "$REPO/.hone-grant/db-drop"
out=$(bash "$WSH" land db-drop 2>&1); rc=$?
[ "$rc" -eq 8 ] || die "an empty grant should still exit 8 (got $rc)"
echo "$out" | grep -q "is empty" || die "the empty-grant refusal should name the reason"
step "empty grant refused (exit 8)"
# (c) With a scoped grant written by the grant helper, which stamps the git
# user and time, it lands and the authorization is recorded in history.
bash "$WSH" grant db-drop "legacy_sessions is unused" >/dev/null || die "grant helper failed"
grep -q "legacy_sessions is unused" "$REPO/.hone-grant/db-drop" || die "grant helper should write the reason"
grep -q "t@t.t" "$REPO/.hone-grant/db-drop" || die "grant helper should stamp the git user"
bash "$WSH" land db-drop >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "granted irreversible land should succeed (got $rc)"
git log --format=%B -1 | grep -q "legacy_sessions is unused" || die "grant text should be recorded in the merge commit body"
step "grant helper wrote a stamped grant; change landed, authorization in history"
# (d) The committed .hone-irreversible-paths extends the built-in signals: a
# change touching a listed glob is gated exactly like destructive SQL. The
# pre-0.19 name .hone-consequential-paths is still honoured.
echo "infra/**" > "$REPO/.hone-irreversible-paths"
WT_C2=$(bash "$WSH" add infra-change) || die "worktree add infra-change"
mkdir -p "$WT_C2/infra"
echo "region = eu-central-1" > "$WT_C2/infra/prod.tf"
(cd "$WT_C2" && git add -A && git commit -qm "feat(infra): touch prod config")
bash "$WSH" land infra-change >/dev/null 2>&1; rc=$?
[ "$rc" -eq 8 ] || die "a .hone-irreversible-paths match should exit 8 (got $rc)"
mv "$REPO/.hone-irreversible-paths" "$REPO/.hone-consequential-paths"
bash "$WSH" land infra-change >/dev/null 2>&1; rc=$?
[ "$rc" -eq 8 ] || die "the legacy .hone-consequential-paths name should still gate (got $rc)"
rm -f "$REPO/.hone-consequential-paths"
bash "$WSH" land infra-change >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "infra change should land once the path list is gone (got $rc)"
step ".hone-irreversible-paths (and its legacy name) gate a listed path (exit 8)"

echo "== 5f. proof gate: real-environment changes need proof or a sign-off =="
# (a) An assertion-class change (no Proof: trailer) is never gated.
WT_A2=$(bash "$WSH" add assert-change) || die "worktree add assert-change"
echo "// assertion-class" > "$WT_A2/src/mathx/plain.js"
(cd "$WT_A2" && git add -A && git commit -qm "chore(mathx): assertion-class change")
bash "$WSH" land assert-change >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "an assertion-class change should land (got $rc)"
step "assertion-class change lands (no Proof: trailer, not gated)"
# (b) A real-environment change with no proof is refused before the merge.
WT_P=$(bash "$WSH" add ui-flow) || die "worktree add ui-flow"
echo "// browser flow" > "$WT_P/src/mathx/flow.js"
(cd "$WT_P" && git add -A && git commit -qm "feat(mathx): checkout flow

Proof: real-environment")
PRE=$(git rev-parse HEAD)
out=$(bash "$WSH" land ui-flow 2>&1); rc=$?
[ "$rc" -eq 7 ] || die "an unproven real-environment change should exit 7 (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "an unproven real-environment change must not touch the trunk"
# A bare trailer (an older Plan) declares no check, so the message stays generic.
echo "$out" | grep -q "The Plan declares this check" && die "a bare trailer should not print a declared check"
step "real-environment change without proof refused (exit 7), trunk untouched"
# (b2) A proof.sh planted in the WORKTREE does not count: land executes only
# the primary tree's reviewed copy, so a change cannot ship its own green stub.
printf '#!/bin/bash\nexit 0\n' > "$WT_P/scripts/proof.sh"
bash "$WSH" land ui-flow >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] || die "a worktree-planted proof stub must not satisfy the gate (got $rc)"
rm -f "$WT_P/scripts/proof.sh"
step "worktree-planted proof.sh stub ignored (exit 7)"
# (b3) A trailer that carries its check after a dash gets that check printed
# back at the gate, so the human never has to go read the Plan for it. Both
# dashes count, and the description survives verbatim.
n=0
for dash in "—" "-"; do
    n=$((n+1))
    WT_D=$(bash "$WSH" add "described-$n") || die "worktree add described-$n"
    echo "// described" > "$WT_D/src/mathx/described.js"
    (cd "$WT_D" && git add -A && git commit -qm "feat(mathx): described flow

Proof: real-environment $dash walk the checkout journey on staging")
    out=$(bash "$WSH" land "described-$n" 2>&1); rc=$?
    [ "$rc" -eq 7 ] || die "a described real-environment change should still exit 7 (got $rc)"
    echo "$out" | grep -q "The Plan declares this check" || die "the gate should label the declared check ($dash)"
    echo "$out" | grep -q "walk the checkout journey on staging" || die "the gate should print the declared check ($dash)"
    bash "$WSH" remove "$WT_D" >/dev/null 2>&1; git branch -D "hone/described-$n" >/dev/null 2>&1
done
step "the trailer's declared check is printed at the gate (both dashes)"
# (b3b) One parser reads every trailer spelling. An uppercase trailer must not
# print its own prefix back as the check, a double-hyphen separator must not
# leave a stray dash, and a bare trailer still gates while declaring nothing.
n=0
for trailer in "PROOF: REAL-ENVIRONMENT — walk the staging journey" \
               "Proof: real-environment -- walk the staging journey" \
               "Proof: real-environment walk the staging journey"; do
    n=$((n+1))
    WT_S=$(bash "$WSH" add "spelling-$n") || die "worktree add spelling-$n"
    echo "// spelled" > "$WT_S/src/mathx/spelled.js"
    (cd "$WT_S" && git add -A && git commit -qm "feat(mathx): a spelled trailer

$trailer")
    out=$(bash "$WSH" land "spelling-$n" 2>&1); rc=$?
    [ "$rc" -eq 7 ] || die "the trailer '$trailer' should gate the land (got $rc)"
    echo "$out" | grep -qx "  walk the staging journey" \
        || die "the parser should print exactly the declared check for '$trailer'"
    bash "$WSH" remove "$WT_S" >/dev/null 2>&1; git branch -D "hone/spelling-$n" >/dev/null 2>&1
done
step "one parser handles an uppercase, double-hyphen, and separatorless trailer"
# (b4) The bootstrap case: a change that writes the proof adapter itself, or one
# of its probes, cannot be proven by the copy land holds, so the refusal tells
# the human to run the branch's own adapter from the worktree.
n=0
for target in scripts/proof.sh scripts/proof-probes/journey.sh; do
    n=$((n+1))
    WT_BS=$(bash "$WSH" add "bootstrap-$n") || die "worktree add bootstrap-$n"
    mkdir -p "$WT_BS/$(dirname "$target")"
    printf '#!/bin/bash\nexit 0\n' > "$WT_BS/$target"
    (cd "$WT_BS" && git add -A && git commit -qm "feat(proof): add $target

Proof: real-environment - run the new adapter by hand")
    out=$(bash "$WSH" land "bootstrap-$n" 2>&1); rc=$?
    [ "$rc" -eq 7 ] || die "a change writing $target should exit 7 (got $rc)"
    echo "$out" | grep -q "land cannot use the copy it has" || die "the gate should explain the bootstrap case for $target"
    echo "$out" | grep -qF "bash scripts/proof.sh bootstrap-$n" || die "the gate should print the by-hand proof command for $target"
    bash "$WSH" remove "$WT_BS" >/dev/null 2>&1; git branch -D "hone/bootstrap-$n" >/dev/null 2>&1
done
# A change that leaves the adapter alone gets no bootstrap hint.
out=$(bash "$WSH" land ui-flow 2>&1)
echo "$out" | grep -q "land cannot use the copy it has" && die "an unrelated change should get no bootstrap hint"
step "a change touching proof.sh or a probe gets the bootstrap instruction"
# (c) A sign-off that names no commit does not satisfy it: an unbound
# sign-off would outlive the code it attested.
mkdir -p "$REPO/.hone-proof"
echo "ran the browser journey against staging: ok" > "$REPO/.hone-proof/ui-flow"
PRE=$(git rev-parse HEAD)
bash "$WSH" land ui-flow >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] || die "a sign-off naming no commit should not satisfy the proof gate (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "an unbound sign-off must not touch the trunk"
step "sign-off naming no commit refused (exit 7)"
# (d) A sign-off bound to an EARLIER commit stops counting once the branch moves.
echo "$(git rev-parse hone/ui-flow) | journey ok" > "$REPO/.hone-proof/ui-flow"
echo "// revised after the sign-off" >> "$WT_P/src/mathx/flow.js"
(cd "$WT_P" && git add -A && git commit -qm "fixup(mathx): revise the flow")
PRE=$(git rev-parse HEAD)
bash "$WSH" land ui-flow >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] || die "a sign-off for an earlier commit should not discharge a newer tip (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "a stale sign-off must not touch the trunk"
step "sign-off bound to an earlier commit refused after the branch moved (exit 7)"
# (e) A sign-off naming the current tip satisfies it. The attest helper writes
# it, stamping the tip commit, the git user, and the time.
bash "$WSH" attest ui-flow "journey ok" >/dev/null || die "attest helper failed"
grep -q "$(git rev-parse hone/ui-flow)" "$REPO/.hone-proof/ui-flow" || die "attest helper should stamp the branch tip"
bash "$WSH" land ui-flow >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a sign-off naming the branch tip should satisfy the proof gate (got $rc)"
step "attest helper wrote a tip-stamped sign-off; change landed"
rm -f "$REPO/.hone-proof/ui-flow"
# The attest helper refuses a change with no branch: nothing to attest.
bash "$WSH" attest no-such-change "nope" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] || die "attest of a nonexistent branch should exit 2 (got $rc)"
step "attest refuses a change with no hone/ branch"
# (e2) The sign-off IS its text. Whitespace records nothing, and the unedited
# placeholder from the usage line reads as evidence while carrying none.
git branch hone/attest-text >/dev/null 2>&1 || die "branch for the attest-text checks"
out=$(bash "$WSH" attest attest-text "   " 2>&1); rc=$?
[ "$rc" -eq 2 ] || die "attest with a whitespace description should exit 2 (got $rc)"
echo "$out" | grep -q "is empty" || die "the empty-description refusal should say so"
[ -f "$REPO/.hone-proof/attest-text" ] && die "a refused attest must not write a sign-off"
# Both persons count: the usage line says "what you ran", and the run skill
# relays the same command to the agent as "what they ran".
for placeholder in "what you ran" "what they ran" \
                   "what you ran and the outcome" "what they ran and the outcome" \
                   "What You Ran" "WHAT THEY RAN AND THE OUTCOME" \
                   '"what you ran and the outcome"' "'what they ran'"; do
    out=$(bash "$WSH" attest attest-text "$placeholder" 2>&1); rc=$?
    [ "$rc" -eq 2 ] || die "attest with the placeholder '$placeholder' should exit 2 (got $rc)"
    echo "$out" | grep -q "placeholder" || die "the placeholder refusal should name the reason"
    [ -f "$REPO/.hone-proof/attest-text" ] && die "a placeholder attest must not write a sign-off"
done
bash "$WSH" attest attest-text "walked the checkout journey on staging: ok" >/dev/null \
    || die "attest should accept a real description"
rm -f "$REPO/.hone-proof/attest-text"; git branch -D hone/attest-text >/dev/null 2>&1
step "attest refuses an empty or placeholder description (exit 2)"
# (f) A green scripts/proof.sh also discharges it, and runs in the change's
# worktree, told which change it is, so it can reach the code under test. The
# adapter is tracked, so the worktree checkout carries it.
cat > "$REPO/scripts/proof.sh" <<'PROOF'
#!/bin/bash
{ echo "arg=$1"; echo "cwd=$PWD"; echo "change=$HONE_CHANGE"; echo "branch=$HONE_BRANCH"
  echo "worktree=$HONE_WORKTREE"; echo "main=$HONE_MAIN_ROOT"; } > "$HONE_MAIN_ROOT/proof-context"
# The code under test must be reachable from here, or this proves nothing.
[ -f "$PWD/src/mathx/flow2.js" ] || exit 1
exit 0
PROOF
git add scripts/proof.sh && git commit -qm "chore: add a passing proof adapter"
WT_P2=$(bash "$WSH" add ui-flow2) || die "worktree add ui-flow2"
echo "// second flow" > "$WT_P2/src/mathx/flow2.js"
(cd "$WT_P2" && git add -A && git commit -qm "feat(mathx): second flow

Proof: real-environment")
bash "$WSH" land ui-flow2 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a green scripts/proof.sh should discharge the proof (got $rc)"
grep -qx "arg=ui-flow2" "$REPO/proof-context" || die "proof.sh must get the change name as \$1"
grep -qx "change=ui-flow2" "$REPO/proof-context" || die "proof.sh must get HONE_CHANGE"
grep -qx "branch=hone/ui-flow2" "$REPO/proof-context" || die "proof.sh must get HONE_BRANCH"
grep -qx "cwd=$REPO/.worktrees/ui-flow2" "$REPO/proof-context" || die "proof.sh must run in the change's worktree"
grep -qx "worktree=$REPO/.worktrees/ui-flow2" "$REPO/proof-context" || die "proof.sh must get HONE_WORKTREE"
grep -qx "main=$REPO" "$REPO/proof-context" || die "proof.sh must get HONE_MAIN_ROOT"
step "green scripts/proof.sh discharged it, run in the worktree with the change named"
rm -f "$REPO/proof-context"
# (g) A red scripts/proof.sh keeps it out (exit 7).
printf '#!/bin/bash\nexit 1\n' > "$REPO/scripts/proof.sh"   # a real-env check that fails
git add scripts/proof.sh && git commit -qm "chore: make the proof adapter fail"
WT_P3=$(bash "$WSH" add ui-flow3) || die "worktree add ui-flow3"
echo "// third flow" > "$WT_P3/src/mathx/flow3.js"
(cd "$WT_P3" && git add -A && git commit -qm "feat(mathx): third flow

Proof: real-environment")
PRE=$(git rev-parse HEAD)
bash "$WSH" land ui-flow3 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] || die "a red scripts/proof.sh should keep a real-environment change out (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "a failed proof must not touch the trunk"
step "real-environment change with a red scripts/proof.sh refused (exit 7)"
# (h) A human sign-off naming the tip satisfies the gate even when the adapter
# is red: the sign-off is checked first, and it says a human ran the real check.
git rev-parse --short hone/ui-flow3 > "$REPO/.hone-proof/ui-flow3"
bash "$WSH" land ui-flow3 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a tip-naming sign-off should land the change despite a red adapter (got $rc)"
step "sign-off naming the tip lands the change (checked before the adapter)"
rm -f "$REPO/.hone-proof/ui-flow3"
# (i) The bootstrap change runs NO adapter, even where the primary tree holds a
# green one. That copy is the copy this change replaces, so a green run would
# prove the old adapter against the new code and auto-land the change. Only the
# human's sign-off discharges it.
cat > "$REPO/scripts/proof.sh" <<'PROOF'
#!/bin/bash
echo "the landed adapter ran" > "$HONE_MAIN_ROOT/proof-context"
exit 0
PROOF
git add scripts/proof.sh && git commit -qm "chore: a green proof adapter again"
WT_BG=$(bash "$WSH" add bootstrap-green) || die "worktree add bootstrap-green"
printf '#!/bin/bash\n# the change rewrites the adapter\nexit 0\n' > "$WT_BG/scripts/proof.sh"
(cd "$WT_BG" && git add -A && git commit -qm "feat(proof): rewrite the adapter

Proof: real-environment - run the new adapter by hand")
PRE=$(git rev-parse HEAD)
out=$(bash "$WSH" land bootstrap-green 2>&1); rc=$?
[ "$rc" -eq 7 ] || die "a bootstrap change must not land on the primary tree's adapter (got $rc)"
[ -f "$REPO/proof-context" ] && die "land must not run the landed adapter for a bootstrap change"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "a bootstrap change must not touch the trunk"
echo "$out" | grep -q "land cannot use the copy it has" || die "the refusal should explain the bootstrap case"
echo "$out" | grep -qF "bash scripts/proof.sh bootstrap-green" || die "the refusal should print the by-hand proof command"
# The human runs the branch's own adapter and attests: that discharges it.
bash "$WSH" attest bootstrap-green "ran the new adapter from the worktree: ok" >/dev/null \
    || die "attest of the bootstrap change failed"
bash "$WSH" land bootstrap-green >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a tip-naming sign-off should land the bootstrap change (got $rc)"
rm -f "$REPO/.hone-proof/bootstrap-green" "$REPO/proof-context"
step "a bootstrap change runs no adapter (exit 7), and a sign-off lands it"
# (j) The adapter change gates on the FILE, not on the trailer. A branch that
# rewrites scripts/proof.sh and declares nothing used to walk straight past this
# gate and merge unseen, which made the adapter the one gate an unattended loop
# could weaken by itself. It now refuses exactly like the declared case.
WT_BQ=$(bash "$WSH" add bootstrap-silent) || die "worktree add bootstrap-silent"
printf '#!/bin/bash\n# weakened, and nothing declared\nexit 0\n' > "$WT_BQ/scripts/proof.sh"
(cd "$WT_BQ" && git add -A && git commit -qm "chore(proof): rewrite the adapter, no trailer")
PRE=$(git rev-parse HEAD)
out=$(bash "$WSH" land bootstrap-silent 2>&1); rc=$?
[ "$rc" -eq 7 ] || die "an undeclared adapter change should exit 7 (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "an undeclared adapter change must not touch the trunk"
[ -f "$REPO/proof-context" ] && die "land must run no adapter for an undeclared adapter change"
echo "$out" | grep -q "land cannot use the copy it has" || die "the refusal should explain the bootstrap case"
echo "$out" | grep -qF "bash scripts/proof.sh bootstrap-silent" || die "the refusal should print the by-hand proof command"
# The refusal names the file change, never a trailer this branch does not carry.
echo "$out" | grep -q "declares real-environment proof" && die "the refusal must not claim an absent trailer"
# The human's sign-off is the only route, exactly as in the declared case.
bash "$WSH" attest bootstrap-silent "ran the new adapter from the worktree: ok" >/dev/null \
    || die "attest of the undeclared adapter change failed"
bash "$WSH" land bootstrap-silent >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a tip-naming sign-off should land the undeclared adapter change (got $rc)"
rm -f "$REPO/.hone-proof/bootstrap-silent" "$REPO/proof-context"
step "an adapter change with no trailer is gated too (exit 7), and a sign-off lands it"
# A probe carries the same weight as the adapter, trailer or not.
WT_BP=$(bash "$WSH" add probe-silent) || die "worktree add probe-silent"
mkdir -p "$WT_BP/scripts/proof-probes"
printf '#!/bin/bash\nexit 0\n' > "$WT_BP/scripts/proof-probes/journey.sh"
(cd "$WT_BP" && git add -A && git commit -qm "chore(proof): add a probe, no trailer")
out=$(bash "$WSH" land probe-silent 2>&1); rc=$?
[ "$rc" -eq 7 ] || die "an undeclared probe change should exit 7 (got $rc)"
echo "$out" | grep -q "land cannot use the copy it has" || die "the probe refusal should explain the bootstrap case"
bash "$WSH" remove "$WT_BP" >/dev/null 2>&1; git branch -D hone/probe-silent >/dev/null 2>&1
step "an undeclared probe change is gated too (exit 7)"
# A change that leaves the adapter alone still needs no proof at all: the gate
# widened to the adapter's own files, and to nothing else.
WT_BN=$(bash "$WSH" add adapter-untouched) || die "worktree add adapter-untouched"
echo "// nowhere near the adapter" > "$WT_BN/src/mathx/untouched.js"
(cd "$WT_BN" && git add -A && git commit -qm "feat(mathx): a change that leaves the adapter alone")
bash "$WSH" land adapter-untouched >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a change away from the adapter should still land ungated (got $rc)"
rm -f "$REPO/proof-context"
step "the widened gate leaves an ordinary change ungated"

echo "== 5g. proof-always: the marker gates every change =="
# (a) With the marker and a green adapter, a change with NO trailer is proven
# anyway. The adapter runs under the same rules: the primary tree's copy, from
# the worktree, with the change in its environment.
cat > "$REPO/scripts/proof.sh" <<'PROOF'
#!/bin/bash
{ echo "arg=$1"; echo "cwd=$PWD"; echo "change=$HONE_CHANGE"; } > "$HONE_MAIN_ROOT/proof-context"
exit 0
PROOF
printf '# every change gets proven here\n' > "$REPO/.hone-proof-always"
git add scripts/proof.sh .hone-proof-always
git commit -qm "chore: prove every change"
WT_AL=$(bash "$WSH" add always-ok) || die "worktree add always-ok"
echo "// no trailer" > "$WT_AL/src/mathx/always.js"
(cd "$WT_AL" && git add -A && git commit -qm "chore(mathx): a change with no Proof trailer")
bash "$WSH" land always-ok >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a green adapter should land a proof-always change (got $rc)"
grep -qx "change=always-ok" "$REPO/proof-context" || die "proof-always should run the adapter with the change named"
grep -qx "cwd=$REPO/.worktrees/always-ok" "$REPO/proof-context" || die "proof-always should run the adapter from the worktree"
rm -f "$REPO/proof-context"
step "the marker proves a change that declared nothing"
# (b) A red adapter keeps an untrailered change out, exit 7.
printf '#!/bin/bash\nexit 1\n' > "$REPO/scripts/proof.sh"
git add scripts/proof.sh && git commit -qm "chore: make the proof adapter fail again"
WT_AR=$(bash "$WSH" add always-red) || die "worktree add always-red"
echo "// still no trailer" > "$WT_AR/src/mathx/always2.js"
(cd "$WT_AR" && git add -A && git commit -qm "chore(mathx): another untrailered change")
PRE=$(git rev-parse HEAD)
bash "$WSH" land always-red >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] || die "a red adapter should refuse a proof-always change (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "a failed proof-always run must not touch the trunk"
# (c) A sign-off naming the tip still discharges it, adapter or not.
git rev-parse --short hone/always-red > "$REPO/.hone-proof/always-red"
bash "$WSH" land always-red >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "a tip-naming sign-off should discharge proof-always (got $rc)"
rm -f "$REPO/.hone-proof/always-red"
step "proof-always refuses on red (exit 7), and a tip sign-off still discharges it"
# (d) The marker with no adapter refuses, and says which of the two to fix.
git rm -q scripts/proof.sh && git commit -qm "chore: drop the proof adapter"
WT_AN=$(bash "$WSH" add always-noadapter) || die "worktree add always-noadapter"
echo "// third" > "$WT_AN/src/mathx/always3.js"
(cd "$WT_AN" && git add -A && git commit -qm "chore(mathx): a third untrailered change")
PRE=$(git rev-parse HEAD)
out=$(bash "$WSH" land always-noadapter 2>&1); rc=$?
[ "$rc" -eq 7 ] || die "the marker without an adapter should exit 7 (got $rc)"
[ "$(git rev-parse HEAD)" = "$PRE" ] || die "the marker without an adapter must not touch the trunk"
# The Do line offers the adapter alone. Removing the marker is project policy,
# addressed to the human, and never a route the refusal hands an agent.
echo "$out" | grep -q "Do: add the adapter" || die "the refusal should tell the reader to add the adapter"
echo "$out" | grep -q "only the human removes it" || die "the refusal should name the marker as the human's policy"
echo "$out" | grep -q "Do:.*marker" && die "the Do line must not offer removing the marker"
# (d2) A sign-off that exists but has gone stale is the precise diagnosis, so it
# is reported first. The marker's no-adapter message would hide the attest route
# and point the human at project policy instead.
git rev-parse HEAD > "$REPO/.hone-proof/always-noadapter"   # names a commit, not the tip
out=$(bash "$WSH" land always-noadapter 2>&1); rc=$?
[ "$rc" -eq 7 ] || die "a stale sign-off under the marker should still exit 7 (got $rc)"
echo "$out" | grep -q "names no commit, or an older one" || die "the stale sign-off should be named as the reason"
echo "$out" | grep -qF "attest always-noadapter" || die "the stale-sign-off refusal should print the attest route"
echo "$out" | grep -q "asks land to prove every change" && die "the marker message must not shadow a stale sign-off"
rm -f "$REPO/.hone-proof/always-noadapter"
# (e) Without the marker, that same change lands untouched by the gate.
git rm -q .hone-proof-always && git commit -qm "chore: stop proving every change"
bash "$WSH" land always-noadapter >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || die "the change should land once the marker is gone (got $rc)"
step "the marker without an adapter refuses (exit 7); removing it reopens the gate"
# (f) status names the marker, and warns while it is uncommitted.
printf '# every change\n' > "$REPO/.hone-proof-always"
out=$(bash "$WSH" status) || die "status failed with the marker present"
echo "$out" | grep -q "NOT committed" || die "status should warn about an uncommitted marker"
git add .hone-proof-always && git commit -qm "chore: commit the proof-always marker"
out=$(bash "$WSH" status) || die "status failed with the marker committed"
echo "$out" | grep -q ".hone-proof-always present (committed)" || die "status should report the committed marker"
git rm -q .hone-proof-always && git commit -qm "chore: drop the marker again"
out=$(bash "$WSH" status) || die "status failed without the marker"
echo "$out" | grep -q ".hone-proof-always" && die "status should say nothing without the marker"
step "status reports the proof-always marker and flags an uncommitted one"

echo "== 5h. tier summaries: land warns about a tier that ran nothing =="
# The adapter reports one line per tier. A tier that matches no test still
# exits 0, so the suite goes green over nothing. land reads the land log and
# names every tier that reported ran=0, without blocking the merge.
cp scripts/run-tests.sh "$REPO/run-tests.orig"
cat > scripts/run-tests.sh <<'EOF'
#!/bin/bash
case "${1:-}" in --all|--unit) shift ;; esac
node -e '
  const {add} = require("./src/mathx/add.js");
  if (add(2,3) !== 5) { console.error("add(2,3) !== 5"); process.exit(1); }
' 2>/dev/null || exit 1
echo "hone tier: unit ran=7"
echo "hone tier: e2e ran=0"
EOF
git add scripts/run-tests.sh && git commit -qm "chore: report tier summaries"
WT_T=$(bash "$WSH" add tier-warn) || die "worktree add tier-warn"
echo "// tiered" > "$WT_T/src/mathx/tiered.js"
(cd "$WT_T" && git add -A && git commit -qm "chore(mathx): a change under a tiered adapter")
out=$(bash "$WSH" land tier-warn 2>&1); rc=$?
[ "$rc" -eq 0 ] || die "the tier warning must not block a green land (got $rc)"
echo "$out" | grep -q "ran no test at all" || die "land should warn about the empty tier"
echo "$out" | grep -q -- "- e2e" || die "the warning should name the empty tier"
echo "$out" | grep -q -- "- unit" && die "the warning must not name a tier that ran tests"
step "land warns about a ran=0 tier and still lands the change"
# An adapter that reports nothing (every older one) draws no warning.
cp "$REPO/run-tests.orig" scripts/run-tests.sh
git add scripts/run-tests.sh && git commit -qm "chore: back to a silent adapter"
rm -f "$REPO/run-tests.orig"
WT_TS=$(bash "$WSH" add tier-silent) || die "worktree add tier-silent"
echo "// silent" > "$WT_TS/src/mathx/silent.js"
(cd "$WT_TS" && git add -A && git commit -qm "chore(mathx): a change under a silent adapter")
out=$(bash "$WSH" land tier-silent 2>&1); rc=$?
[ "$rc" -eq 0 ] || die "a silent adapter should land normally (got $rc)"
echo "$out" | grep -q "ran no test at all" && die "a silent adapter should draw no tier warning"
step "an adapter that reports no tiers draws no warning"

echo "== 6. status: the control surface at a glance =="
out=$(bash "$WSH" status) || die "status failed"
echo "$out" | grep -q "hooks: on" || die "status should report hooks on"
echo "$out" | grep -q "run-tests=yes" || die "status should see the test adapter"
echo "$out" | grep -q "plans: none pending" || die "status should report no pending Plans"
echo "$out" | grep -q "worktrees: none in flight" || die "status should report no worktrees"
echo "$out" | grep -q "settings deny rules: MISSING" || die "status should flag missing deny rules"
# A partial set is still MISSING, and the warning names only what is absent:
# the semantic comparison against the canonical list, not a single-rule probe.
mkdir -p "$REPO/.claude"
printf '{"permissions":{"deny":["Edit(./scripts/run-tests.sh)"]}}\n' > "$REPO/.claude/settings.json"
out=$(bash "$WSH" status) || die "status failed with a partial deny set"
echo "$out" | grep -q "settings deny rules: MISSING" || die "status should flag a partial deny set"
echo "$out" | grep -qF 'Edit(./scripts/proof.sh)' || die "status should name a missing rule"
echo "$out" | grep -qF 'Edit(./scripts/run-tests.sh)' && die "status should not name a present rule"
# The present-case: the full canonical list, in the bare Edit(x) spelling to
# pin that the comparison is semantic. Probing a rule form nobody writes reads
# as MISSING forever; probing one Claude Code rejects (Write(path)) is worse,
# since it pushes an inert rule. Edit(path) is the only form file tools match.
{ echo '{"permissions":{"deny":['
  grep -vE '^[[:space:]]*(#|$)' "$PLUGIN_ROOT/templates/settings/deny-rules.txt" \
      | sed -e 's/.*/"&",/' -e '$ s/,$//' -e 's|Edit(\./|Edit(|'
  echo ']}}'
} > "$REPO/.claude/settings.json"
out=$(bash "$WSH" status) || die "status failed with deny rules present"
echo "$out" | grep -q "settings deny rules: present" || die "status should accept the full set in the bare spelling"
grep -qF 'Write(./scripts/run-tests.sh)' "$PLUGIN_ROOT/README.md" && die "README must not teach Write(path) rules; Claude Code rejects them"
rm -rf "$REPO/.claude"
out=$(bash "$WSH" status) || die "status failed"
mkdir -p "$REPO/.plans" && echo "# Plan" > "$REPO/.plans/queued.md"
touch "$REPO/.hone-off"
out=$(bash "$WSH" status) || die "status failed with markers present"
echo "$out" | grep -q "hooks: OFF" || die "status should report .hone-off"
echo "$out" | grep -q "plan pending: .plans/queued.md" || die "status should list the pending Plan"
rm -f "$REPO/.hone-off" "$REPO/.plans/queued.md"
step "status reports hooks, adapters, plans, worktrees, deny rules"

echo "== 6b. a conflicting land exits 9, tree restored =="
WT_CA=$(bash "$WSH" add conflict-a) || die "worktree add conflict-a"
WT_CB=$(bash "$WSH" add conflict-b) || die "worktree add conflict-b"
echo "version A" > "$WT_CA/README.md"; (cd "$WT_CA" && git add -A && git commit -qm "feat: a")
echo "version B" > "$WT_CB/README.md"; (cd "$WT_CB" && git add -A && git commit -qm "feat: b")
bash "$WSH" land conflict-a >/dev/null 2>&1 || die "first land should succeed"
bash "$WSH" land conflict-b >/dev/null 2>&1; rc=$?
[ "$rc" -eq 9 ] || die "a conflicting land should exit 9 (got $rc)"
[ -z "$(git status --porcelain -uno)" ] || die "a conflicted land should leave the tracked tree clean"
git show-ref --verify --quiet refs/heads/hone/conflict-b || die "the conflicting branch should survive as evidence"
step "conflict aborted with its own exit code (9), tree clean, branch kept"
bash "$WSH" remove "$WT_CB" >/dev/null 2>&1; git branch -D hone/conflict-b >/dev/null 2>&1

echo "== 6c. landed: the artifact predicate an orchestrator polls =="
# conflict-a landed above: merge commit present, branch and worktree gone.
out=$(bash "$WSH" landed conflict-a) || die "landed conflict-a should exit 0"
[ "$out" = "landed" ] || die "landed should print 'landed' (got: $out)"
# conflict-b never merged: no merge commit, so pending even with no branch left.
out=$(bash "$WSH" landed conflict-b); rc=$?
[ "$rc" -eq 1 ] || die "an unmerged change should be pending, exit 1 (got $rc)"
[ "$out" = "pending" ] || die "landed should print 'pending' (got: $out)"
# A change still in flight is pending: its branch and worktree are the claim.
WT_IF=$(bash "$WSH" add inflight-x) || die "worktree add inflight-x"
out=$(bash "$WSH" landed inflight-x); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "pending" ] || die "an in-flight change should be pending"
bash "$WSH" remove "$WT_IF" >/dev/null 2>&1
# A Plan surviving at HEAD keeps the change pending: consolidate did not finish.
# -f: track the Plan even if this scratch repo's .gitignore covers .plans/.
mkdir -p "$REPO/.plans" && echo "# Plan" > "$REPO/.plans/conflict-a.md"
git add -f .plans/conflict-a.md && git commit -qm "chore(plan): conflict-a"
out=$(bash "$WSH" landed conflict-a); rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "pending" ] || die "a surviving Plan should keep the change pending"
git rm -q .plans/conflict-a.md && git commit -qm "chore: drop the leftover plan"
bash "$WSH" landed conflict-a >/dev/null || die "landed should be 0 again after the Plan is gone"
step "landed reads the merge commit, claim, and Plan, never a report"

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
