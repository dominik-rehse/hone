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

echo "== 5. land: merge to primary + re-verify =="
git merge --no-ff -q hone/mathx-add -m "merge: mathx-add" || die "merge"
bash scripts/run-tests.sh >/dev/null 2>&1 || die "suite red in primary after merge"
step "merged and suite green in the primary tree"

echo "== 6. remove the worktree =="
bash "$WSH" remove "$WT" || die "worktree remove"
[ -d "$WT" ] && die "worktree still present" || step "worktree removed"
git show-ref --verify --quiet refs/heads/hone/mathx-add && die "merged branch should be deleted with its worktree" || step "merged branch hone/mathx-add deleted"

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
