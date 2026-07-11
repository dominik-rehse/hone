#!/bin/bash
# Mechanical proof that hone's hooks fire correctly. Builds a throwaway git repo,
# drives each hook script the way Claude Code would (JSON on stdin, or Stop with
# no input), and asserts the decision. Run: bash test/hooks_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$PLUGIN_ROOT/hooks/guard.sh"
GATE="$PLUGIN_ROOT/hooks/gate.sh"
NAG="$PLUGIN_ROOT/hooks/nag.sh"
BASH_GUARD="$PLUGIN_ROOT/hooks/bash-guard.sh"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

# Run guard.sh with a Write to $1, from cwd $2; echo the raw JSON (empty = allow).
guard_write() { echo "{\"tool_input\":{\"file_path\":\"$1\"}}" | (cd "$2" && bash "$GUARD"); }
# True if the guard output denies.
denied() { echo "$1" | grep -q '"permissionDecision":"deny"'; }

REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
cd "$REPO" || exit 1
git init -q && git symbolic-ref HEAD refs/heads/main
git config user.email t@t.t; git config user.name t
mkdir -p src/auth tests docs/notes docs/decisions .plans scripts
printf '.worktrees/\n.plans/\n.hone-off\n.hone-nag-enforce\n' > .gitignore
echo "# seed" > README.md
# Keep the src/auth dir in the tree so it exists in a linked worktree checkout.
echo "// seed" > src/auth/.keep
git add -A && git commit -qm seed

echo "== guard: primary tree =="

# 1. New src/ file with no test, in the primary tree → deny (rule 1 or 2).
out=$(guard_write "src/auth/login.ts" "$REPO")
denied "$out" && ok "new src/ file in primary tree denied" || bad "should deny new src/ in primary tree"

# 2. A test file is always allowed (RED artifact), even in the primary tree?
#    No — rule 1 blocks durable edits in the primary tree, and tests/ is durable.
out=$(guard_write "src/auth/login.test.ts" "$REPO")
denied "$out" && ok "test file in primary tree denied (durable, merge-only)" || bad "should deny durable test in primary tree"

# 3. The ephemeral Plan is writable in the primary tree.
out=$(guard_write ".plans/auth-login.md" "$REPO")
denied "$out" && bad ".plans/ should be writable in primary tree" || ok ".plans/ writable in primary tree"

# 4. A root config file is not a durable artifact → allowed.
out=$(guard_write "package.json" "$REPO")
denied "$out" && bad "package.json should be allowed" || ok "non-durable root file allowed"

echo "== guard: inside a worktree (test-first) =="
git worktree add -q -b hone/auth-login .worktrees/auth-login HEAD
WT="$REPO/.worktrees/auth-login"

# 5. New src/ file with no test, inside a worktree → deny (rule 2 test-first).
out=$(guard_write "src/auth/login.ts" "$WT")
denied "$out" && ok "new src/ without test denied in worktree" || bad "should deny new src/ without test"

# 6. The test file (RED artifact) is allowed in the worktree.
out=$(guard_write "src/auth/login.test.ts" "$WT")
denied "$out" && bad "test file should be allowed in worktree" || ok "test file allowed in worktree (RED)"

# 7. Now the test exists → the src file is allowed.
touch "$WT/src/auth/login.test.ts"
out=$(guard_write "src/auth/login.ts" "$WT")
denied "$out" && bad "src should be allowed once its test exists" || ok "src allowed once test exists"

echo "== guard: .hone-off disables it =="
touch "$REPO/.hone-off"
out=$(guard_write "src/auth/login.ts" "$REPO")
denied "$out" && bad ".hone-off should disable the guard" || ok ".hone-off disables the guard"
rm -f "$REPO/.hone-off"

echo "== bash-guard: tamper resistance =="
bg() { echo "{\"tool_input\":{\"command\":\"$1\"}}" | (cd "$REPO" && bash "$BASH_GUARD"); }
echo "$(bg 'git commit --no-verify -m x')" | grep -q '"deny"' && ok "--no-verify denied" || bad "--no-verify should be denied"
echo "$(bg 'touch .hone-off')" | grep -q '"deny"' && ok "touch .hone-off denied" || bad "touch .hone-off should be denied"
echo "$(bg 'sed -i s/x/y/ scripts/run-tests.sh')" | grep -q '"ask"' && ok "editing run-tests.sh escalated" || bad "editing adapter should ask"
echo "$(bg 'ls -la')" | grep -q 'permissionDecision' && bad "benign command should pass silently" || ok "benign command passes"

echo "== gate: blocks a red suite, passes a green one =="
# Adapter that fails; make src dirty so the gate runs.
cat > "$REPO/scripts/run-tests.sh" <<'EOF'
#!/bin/bash
exit 1
EOF
echo "x" >> "$REPO/src/auth/login.ts" 2>/dev/null || { mkdir -p "$REPO/src/auth"; echo x > "$REPO/src/auth/login.ts"; }
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
echo "$out" | grep -q '"decision":"block"' && ok "red suite blocks the stop" || bad "red suite should block"
# Green adapter → no block, and a green receipt naming what ran.
echo 'exit 0' > "$REPO/scripts/run-tests.sh"
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
echo "$out" | grep -q '"decision":"block"' && bad "green suite should not block" || ok "green suite passes the gate"
echo "$out" | grep -q '"systemMessage":"hone gate: green (tests (--unit))"' && ok "green gate emits a receipt naming the checks" || bad "green gate should emit a receipt"
# Clean tree (no src/test changes) → gate is a no-op even with a failing adapter.
echo 'exit 1' > "$REPO/scripts/run-tests.sh"
(cd "$REPO" && git add -A && git commit -qm work)
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
echo "$out" | grep -q '"decision":"block"' && bad "clean tree should not run the gate" || ok "clean tree skips the gate"

echo "== gate: tier escalation on a hone/<change> branch =="
# A tier-sensitive adapter: green on unit, red on --all. Proves which tier ran.
git -C "$REPO" checkout -q -b hone/verify-tier
cat > "$REPO/scripts/run-tests.sh" <<'EOF'
#!/bin/bash
case "${1:-}" in --all) exit 1 ;; *) exit 0 ;; esac
EOF
(cd "$REPO" && git add -A && git commit -qm "tier adapter")
# Clean tree on a hone/* branch (committed, about to land) → --all runs → block.
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
echo "$out" | grep -q '"decision":"block"' && ok "clean hone/* branch runs --all (pre-land full check)" || bad "clean hone/* branch should escalate to --all and block"
# Dirty src → the fast unit tier runs (green), so the red-green loop stays cheap.
echo "// edit" >> "$REPO/src/auth/login.ts"
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
echo "$out" | grep -q '"decision":"block"' && bad "dirty tree should run the unit tier (pass), not --all" || ok "dirty tree runs the unit tier (loop stays fast)"
git -C "$REPO" checkout -q -- src/auth/login.ts

echo "== nag: leftover Plan, oversized Note, orphan Note =="
echo "# Plan" > "$REPO/.plans/ghost.md"   # no matching worktree
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "ghost.md has no .worktrees" && ok "leftover Plan flagged" || bad "should flag leftover Plan"

# Nested slug (the plan skill derives <area>/<change> mirroring src/).
mkdir -p "$REPO/.plans/auth"
echo "# Plan" > "$REPO/.plans/auth/ghost-nested.md"   # no matching worktree
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q ".plans/auth/ghost-nested.md has no .worktrees/auth/ghost-nested" && ok "nested leftover Plan flagged" || bad "should flag nested leftover Plan"

# A nested Plan whose worktree exists is active work — not flagged.
mkdir -p "$REPO/.worktrees/auth/ghost-nested"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "ghost-nested" && bad "nested Plan with live worktree should not be flagged" || ok "nested Plan with live worktree not flagged"
rm -rf "$REPO/.worktrees/auth" "$REPO/.plans/auth"

printf 'line\n%.0s' $(seq 1 60) > "$REPO/docs/notes/auth.md"   # 60 lines > cap; src/auth exists
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "docs/notes/auth.md is 60 lines" && ok "oversized Note flagged" || bad "should flag oversized Note"

echo "# orphan" > "$REPO/docs/notes/ghostarea.md"   # no src/ghostarea/
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "docs/notes/ghostarea.md has no src/ghostarea/" && ok "orphan Note flagged" || bad "should flag orphan Note"

# Enforce marker turns nag into a block.
touch "$REPO/.hone-nag-enforce"
out=$(cd "$REPO" && echo '{}' | bash "$NAG")
echo "$out" | grep -q '"decision":"block"' && ok ".hone-nag-enforce makes nag block" || bad "nag-enforce should block"

echo
echo "== worktree.sh add/landable/remove =="
rm -f "$REPO/.hone-nag-enforce"
WSH="$PLUGIN_ROOT/scripts/worktree.sh"
(cd "$REPO" && bash "$WSH" add feature-x >/dev/null) && [ -d "$REPO/.worktrees/feature-x" ] && ok "worktree add created .worktrees/feature-x" || bad "worktree add failed"
(cd "$REPO/.worktrees/feature-x" && echo y > src_x && git add -A && git commit -qm x)
out=$(cd "$REPO" && bash "$WSH" landable) && echo "$out" | grep -q "feature-x" && ok "landable lists the ahead worktree" || bad "landable should list feature-x"
(cd "$REPO" && bash "$WSH" remove "$REPO/.worktrees/feature-x") && [ ! -d "$REPO/.worktrees/feature-x" ] && ok "worktree remove cleaned up" || bad "worktree remove failed"
out=$(cd "$REPO" && bash "$WSH" remove "/tmp/not-ours" 2>&1); [ $? -eq 3 ] || echo "$out" | grep -q "did not create it" && ok "remove refuses foreign path (exit 3)" || bad "remove should refuse foreign path"

echo
echo "== guard: durable perimeter (db/ default, .hone-durable-paths) =="
# db/ is durable by default → denied in the primary tree.
out=$(guard_write "db/migrations/0001_init.sql" "$REPO")
denied "$out" && ok "db/ denied in primary tree" || bad "db/ should be durable by default"
# ...but writable in a worktree (rule 1 is primary-tree-only; rule 2 is src/-only).
out=$(guard_write "db/migrations/0001_init.sql" "$WT")
denied "$out" && bad "db/ should be writable in a worktree" || ok "db/ writable in a worktree"
# .hone-durable-paths EXTENDS the perimeter: a dir prefix and an exact file.
printf '# project perimeter\ndeploy/\ntsconfig.json\n' > "$REPO/.hone-durable-paths"
out=$(guard_write "deploy/systemd/app.service" "$REPO")
denied "$out" && ok "configured dir (deploy/) denied in primary tree" || bad "deploy/ should be denied via .hone-durable-paths"
out=$(guard_write "tsconfig.json" "$REPO")
denied "$out" && ok "configured file (tsconfig.json) denied in primary tree" || bad "tsconfig.json should be denied via .hone-durable-paths"
out=$(guard_write "tsconfig.json.bak" "$REPO")
denied "$out" && bad "tsconfig.json.bak should not match the tsconfig.json entry" || ok "prefix does not overmatch (tsconfig.json.bak allowed)"
out=$(guard_write "package.json" "$REPO")
denied "$out" && bad "unlisted root file should stay allowed" || ok "unlisted root file still allowed"
rm -f "$REPO/.hone-durable-paths"
out=$(guard_write "deploy/systemd/app.service" "$REPO")
denied "$out" && bad "deploy/ should be allowed without .hone-durable-paths" || ok "perimeter shrinks back when the file is removed"

echo
echo "== nag: zero-deletion change (advisory, pre-land) =="
# The auth-login worktree: commit everything so the tree is clean on hone/auth-login,
# with a purely additive diff vs the primary branch.
(cd "$WT" && echo "new behaviour" > added.txt && git add -A && git commit -qm "feat: additive only")
out=$(cd "$WT" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "deletes nothing" && ok "purely additive pre-land change flagged" || bad "should flag a zero-deletion change on a clean hone/* branch"
# Advisory even under .hone-nag-enforce: it rides along but never blocks alone.
touch "$WT/.hone-nag-enforce"
out=$(cd "$WT" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q '"decision":"block"' && bad "advisory-only finding should not block under enforce" || ok "zero-deletion finding stays advisory under enforce"
rm -f "$WT/.hone-nag-enforce"
# A change that deletes something is not flagged.
(cd "$WT" && sed -i '1d' README.md && git add -A && git commit -qm "chore: cut a line")
out=$(cd "$WT" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "deletes nothing" && bad "change with deletions should not be flagged" || ok "change with deletions passes"

echo
echo "== nag: merged hone/* branch left behind =="
git -C "$REPO" branch hone/landed-ghost HEAD
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "hone/landed-ghost is fully merged and has no worktree" && ok "leftover merged branch flagged" || bad "should flag a merged hone/* branch with no worktree"
git -C "$REPO" branch -d hone/landed-ghost >/dev/null 2>&1
# A branch attached to a live worktree (hone/auth-login) is active work — check
# it was NOT flagged in the run above.
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "hone/auth-login is fully merged" && bad "branch with live worktree should not be flagged" || ok "branch with live worktree not flagged"

echo
echo "== worktree.sh remove: branch and empty-dir hygiene =="
# The earlier remove of feature-x (unmerged, ahead) must have KEPT its branch.
git -C "$REPO" show-ref --verify --quiet refs/heads/hone/feature-x && ok "unmerged branch survives remove (evidence)" || bad "unmerged branch should survive remove"
git -C "$REPO" branch -D hone/feature-x >/dev/null 2>&1
# A merged change: nested slug, commit, merge, remove → branch deleted, empty
# parent dir swept.
WT2=$(cd "$REPO" && bash "$WSH" add area2/nested-change) || bad "nested worktree add failed"
(cd "$WT2" && echo data > cut-me.txt && git add -A && git commit -qm "feat: nested change")
(cd "$REPO" && git merge --no-ff -q hone/area2/nested-change -m "merge: nested-change")
(cd "$REPO" && bash "$WSH" remove "$WT2" >/dev/null 2>&1) || bad "nested worktree remove failed"
git -C "$REPO" show-ref --verify --quiet refs/heads/hone/area2/nested-change && bad "merged branch should be deleted at remove" || ok "merged branch deleted at remove"
[ -d "$REPO/.worktrees/area2" ] && bad "empty parent dir should be swept" || ok "empty nested parent dir swept"
[ -d "$REPO/.worktrees" ] && ok ".worktrees/ itself is kept" || bad ".worktrees/ itself should be kept"

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
