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
DIRTY_GUARD="$PLUGIN_ROOT/hooks/dirty-guard.sh"

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
printf '.worktrees/\n.plans/\n.hone-off\n' > .gitignore
echo "# seed" > README.md
# Keep the src/auth dir in the tree so it exists in a linked worktree checkout.
echo "// seed" > src/auth/.keep
git add -A && git commit -qm seed

echo "== guard: primary tree =="

# 1. New src/ file with no test, in the primary tree → deny (rule 1 or 2).
out=$(guard_write "src/auth/login.ts" "$REPO")
denied "$out" && ok "new src/ file in primary tree denied" || bad "should deny new src/ in primary tree"

# 2. A test file is always allowed (RED artifact), even in the primary tree?
#    No: rule 1 blocks durable edits in the primary tree, and tests/ is durable.
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

# 7b. pytest's prefix convention is a test file too (the RED artifact): a new
# colocated test_*.py must be writable, not mistaken for untested prod code.
out=$(guard_write "src/auth/test_login.py" "$WT")
denied "$out" && bad "pytest prefix test file should be allowed in worktree" || ok "pytest prefix test file allowed (RED)"

echo "== guard: land-gate sign-offs denied in every tree =="
out=$(guard_write ".hone-grant/db-drop" "$REPO")
denied "$out" && ok ".hone-grant/ write denied in primary tree" || bad "should deny .hone-grant/ writes"
out=$(guard_write ".hone-proof/ui-flow" "$WT")
denied "$out" && ok ".hone-proof/ write denied in a worktree" || bad "should deny .hone-proof/ writes in a worktree"

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
# The land gates' sign-offs are reserved to the human: any write route into
# .hone-grant/ or .hone-proof/, including the helpers, is denied to the agent.
echo "$(bg 'echo signed > .hone-proof/ui-flow')" | grep -q '"deny"' && ok "writing a proof sign-off denied" || bad "writing .hone-proof/ should be denied"
echo "$(bg 'mkdir -p .hone-grant && touch .hone-grant/db-drop')" | grep -q '"deny"' && ok "creating a grant denied" || bad "creating .hone-grant/<change> should be denied"
echo "$(bg 'bash scripts/worktree.sh grant db-drop reason')" | grep -q '"deny"' && ok "grant helper denied to the agent" || bad "worktree.sh grant should be denied"
echo "$(bg 'bash scripts/worktree.sh attest db-drop ran-it')" | grep -q '"deny"' && ok "attest helper denied to the agent" || bad "worktree.sh attest should be denied"
echo "$(bg 'cat .hone-grant/db-drop')" | grep -q 'permissionDecision' && bad "reading a grant should pass silently" || ok "reading a grant allowed"
# Mutators beyond the creation verbs are denied too: rule 1b's op list is a
# superset of rule 2's, so truncate/dd/sed -i can't slip a sign-off through.
echo "$(bg 'truncate -s0 .hone-grant/db-drop')" | grep -q '"deny"' && ok "truncate of a grant denied" || bad "truncate into .hone-grant/ should be denied"
echo "$(bg 'sed -i s/x/approved/ .hone-proof/ui-flow')" | grep -q '"deny"' && ok "sed -i of a sign-off denied" || bad "sed -i into .hone-proof/ should be denied"
echo "$(bg 'dd of=.hone-grant/db-drop')" | grep -q '"deny"' && ok "dd into a grant denied" || bad "dd into .hone-grant/ should be denied"
# The committed policy files bound the enforcement perimeter: mutating one asks.
echo "$(bg 'sed -i s/a/b/ .hone-durable-paths')" | grep -q '"ask"' && ok "editing .hone-durable-paths escalated" || bad "editing a policy file should ask"
echo "$(bg 'echo db/ >> .hone-irreversible-paths')" | grep -q '"ask"' && ok "appending to .hone-irreversible-paths escalated" || bad "appending to a policy file should ask"
# The .hone-proof-always marker is policy too, and deleting it is the cheapest
# way past the land proof gate, so removing or rewriting it escalates.
echo "$(bg 'rm .hone-proof-always')" | grep -q '"ask"' && ok "removing .hone-proof-always escalated" || bad "removing the proof-always marker should ask"
echo "$(bg 'echo x > .hone-proof-always')" | grep -q '"ask"' && ok "rewriting .hone-proof-always escalated" || bad "rewriting the proof-always marker should ask"
# messages.sh carries hone's own prose, and it belongs to the same plugin-side
# class as the other hooks the pattern already lists.
echo "$(bg 'sed -i s/x/y/ hooks/messages.sh')" | grep -q '"ask"' && ok "editing hooks/messages.sh escalated" || bad "editing a plugin hook file should ask"
# A HEAD-move in the primary tree races other sessions → ask; the same op inside
# a linked worktree is isolated → silent.
echo "$(bg 'git checkout some-commit')" | grep -q '"ask"' && ok "git checkout in primary tree escalated" || bad "checkout in primary should ask"
echo "$(bg 'git stash push -- IDEAS.md')" | grep -q '"ask"' && ok "git stash in primary tree escalated" || bad "stash in primary should ask"
echo "$(bg 'git reset --hard HEAD^')" | grep -q '"ask"' && ok "git reset --hard in primary tree escalated" || bad "hard reset in primary should ask"
bgwt() { echo "{\"tool_input\":{\"command\":\"$1\"}}" | (cd "$WT" && bash "$BASH_GUARD"); }
echo "$(bgwt 'git checkout -- src/auth/login.ts')" | grep -q '"ask"' && bad "HEAD-move inside a worktree should not ask" || ok "HEAD-move allowed inside a worktree"
# A tool that writes its own files carries neither a write construct nor a path,
# so rule 2 cannot see it. Rule 4 matches it by name, in the primary tree only.
echo "$(bg 'bun add -d dprint@latest')" | grep -q '"ask"' && ok "a package manager in the primary tree escalated" || bad "bun add in primary should ask"
echo "$(bg 'bunx biome migrate --write')" | grep -q '"ask"' && ok "a migration tool in the primary tree escalated" || bad "biome migrate in primary should ask"
echo "$(bg 'bun test')" | grep -q 'permissionDecision' && bad "a read-only runner should pass silently" || ok "a non-writing subcommand passes"
# A bare sync install writes no durable file and is the sanctioned next step
# after a land that changed the lockfile. Flags do not change that.
for sync in 'bun install' 'npm ci' 'pnpm install' 'npm i' \
            'bun install --frozen-lockfile' 'npm ci --ignore-scripts' \
            'poetry install' 'uv sync' 'bun install && bun test'; do
    echo "$(bg "$sync")" | grep -q 'permissionDecision' \
        && bad "a bare sync install should pass rule 4: $sync" \
        || ok "sync install passes rule 4: $sync"
done
# An install that NAMES a package rewrites the manifest, so it still escalates.
for mutating in 'npm install lodash' 'bun add x' 'poetry add y' 'npm i -g typescript' \
                'pnpm install --filter web lodash' 'cargo install ripgrep' 'bun update'; do
    echo "$(bg "$mutating")" | grep -q '"ask"' \
        && ok "a mutating install escalates: $mutating" \
        || bad "an install naming a package should ask: $mutating"
done
echo "$(bgwt 'bun add -d dprint@latest')" | grep -q 'permissionDecision' && bad "a worktree is where dependency work belongs" || ok "a package manager inside a worktree passes"
# Rules 3 and 4 must judge the tree the command WRITES IN. A hook runs in the
# session cwd, so a command that cds into a worktree first is worktree work
# even though the hook stands in the primary tree.
echo "$(bg "cd $WT && bun add -d dprint@latest")" | grep -q 'permissionDecision' && bad "a cd into a worktree makes this worktree work" || ok "cd into a worktree passes rule 4"
echo "$(bg "cd $WT && git checkout some-commit")" | grep -q 'permissionDecision' && bad "a cd into a worktree makes this worktree work" || ok "cd into a worktree passes rule 3"
# Fail closed wherever the target is unclear, so the escalation is kept.
echo "$(bg "cd $WT && cd $REPO && bun add -d dprint@latest")" | grep -q '"ask"' && ok "a second cd fails closed and still asks" || bad "two cds should fail closed"
echo "$(bg 'cd /nonexistent-tree && bun add -d dprint@latest')" | grep -q '"ask"' && ok "an unusable cd target fails closed and still asks" || bad "a missing cd target should fail closed"
echo "$(bg 'bun add -d dprint@latest && cd '"$WT")" | grep -q '"ask"' && ok "a trailing cd does not excuse a primary-tree write" || bad "a cd that is not first should fail closed"

echo "== dirty-guard: what a shell command leaves dirty in the primary tree =="
dg() { echo '{"tool_input":{"command":"bun add -d dprint"}}' | (cd "$1" && bash "$DIRTY_GUARD"); }
blocked() { echo "$1" | grep -q '"decision":"block"'; }

# A clean primary tree passes. The hook reads the tree, never the command.
out=$(dg "$REPO")
blocked "$out" && bad "clean primary tree should pass" || ok "clean primary tree passes"

# A tracked durable path left dirty → block, naming the path and the restore.
echo "// touched" >> "$REPO/src/auth/.keep"
out=$(dg "$REPO")
blocked "$out" && ok "dirty durable path in the primary tree blocks" || bad "should block a dirty durable path"
echo "$out" | grep -q 'src/auth/.keep' && ok "the block names the dirty path" || bad "the block should name the path"
echo "$out" | grep -q 'git checkout HEAD --' && ok "the restore command names HEAD, not the index" || bad "the restore should name HEAD"
git -C "$REPO" checkout HEAD -- src/auth/.keep

# An untracked durable path blocks too, and no checkout brings it back, so the
# message must not offer one.
echo "// new" > "$REPO/src/auth/extra.ts"
out=$(dg "$REPO")
blocked "$out" && ok "untracked durable path blocks" || bad "should block an untracked durable path"
echo "$out" | grep -q 'git checkout HEAD --' && bad "no checkout restores an untracked path" || ok "no restore command offered for an untracked path"
rm -f "$REPO/src/auth/extra.ts"

# A non-durable root file is the project's business.
echo '{}' > "$REPO/package.json"
out=$(dg "$REPO")
blocked "$out" && bad "non-durable package.json should pass" || ok "non-durable root file passes"

# .hone-durable-paths extends the set, so the same file now blocks. This is the
# package-manager case in full: 'bun add' rewrites package.json from inside its
# own process, so guard.sh sees no file path and bash-guard rule 2 sees no write
# construct. Only the effect gives it away.
printf 'package.json\n' > "$REPO/.hone-durable-paths"
(cd "$REPO" && git add .hone-durable-paths && git commit -qm "policy")
out=$(dg "$REPO")
blocked "$out" && ok "a path from .hone-durable-paths blocks" || bad "should block a listed durable path"

# The same dirty durable path inside a worktree is the work in flight → silent.
out=$(dg "$WT")
blocked "$out" && bad "a worktree is where durable work belongs" || ok "dirty durable path in a worktree passes"

# .hone-off disables it like the rest of hone.
touch "$REPO/.hone-off"
out=$(dg "$REPO")
blocked "$out" && bad ".hone-off should disable the dirty-guard" || ok ".hone-off disables the dirty-guard"
rm -f "$REPO/.hone-off" "$REPO/package.json"

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

echo "== gate: durable dirt outside src/ and tests/ still runs the suite =="
# A dependency sweep leaves the manifest, the lockfile, and a tool config dirty
# while src/ and tests/ stay clean. The gate used to no-op there, and a red lint
# survived the turn. The adapter is red, so a block proves the gate ran.
echo "note" > "$REPO/docs/notes/perimeter.md"
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
echo "$out" | grep -q '"decision":"block"' && ok "dirty docs/ runs the suite" || bad "docs/ dirt should run the gate"
rm -f "$REPO/docs/notes/perimeter.md"
# The project's own perimeter counts the same: .hone-durable-paths lists
# package.json here, which is the dependency sweep in full.
echo '{}' > "$REPO/package.json"
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
echo "$out" | grep -q '"decision":"block"' && ok "a dirty .hone-durable-paths entry runs the suite" || bad "a listed durable path should run the gate"
rm -f "$REPO/package.json"
# A dirty path outside the perimeter is the project's business, so the gate
# stays a no-op and the turn stays cheap.
echo "scratch" > "$REPO/scratch.txt"
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
echo "$out" | grep -q '"decision":"block"' && bad "non-durable dirt should not run the gate" || ok "non-durable dirt keeps the gate a no-op"
rm -f "$REPO/scratch.txt"

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

echo "== nag: leftover Plan (landed evidence only), oversized Note, orphan Note =="
# No worktree and no landed evidence = the normal plan→run gap: pending, not
# stale. No per-Plan finding; one aggregate advisory line instead.
echo "# Plan" > "$REPO/.plans/ghost.md"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "ghost.md" && bad "pending Plan should not be flagged by name" || ok "pending Plan (no landed evidence) not flagged"
echo "$out" | grep -q "1 Plan(s) pending run" && ok "pending Plans surface as one aggregate advisory" || bad "should emit an aggregate pending-Plans advisory"

# Evidence 1: land's merge commit in HEAD's history → the finding fires.
git -C "$REPO" commit -q --allow-empty -m "Merge branch 'hone/ghost'"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q ".plans/ghost.md survived its landing" && ok "Plan with landing merge commit flagged" || bad "should flag Plan whose merge commit is in history"

# Evidence 2: a surviving fully-merged hone/<change> branch.
echo "# Plan" > "$REPO/.plans/ghost2.md"
git -C "$REPO" branch hone/ghost2 HEAD
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q ".plans/ghost2.md survived its landing" && ok "Plan with fully-merged surviving branch flagged" || bad "should flag Plan whose merged branch survives"
git -C "$REPO" branch -d hone/ghost2 >/dev/null 2>&1
rm -f "$REPO/.plans/ghost2.md"

# Nested slug (the plan skill derives <area>/<change> mirroring src/): the
# recursive scan still finds it, evidence rules unchanged.
mkdir -p "$REPO/.plans/auth"
echo "# Plan" > "$REPO/.plans/auth/ghost-nested.md"
git -C "$REPO" commit -q --allow-empty -m "Merge branch 'hone/auth/ghost-nested'"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q ".plans/auth/ghost-nested.md survived its landing" && ok "nested landed Plan flagged" || bad "should flag nested landed Plan"

# A nested Plan whose worktree exists is active work, not flagged even with
# landed evidence in history.
mkdir -p "$REPO/.worktrees/auth/ghost-nested"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "ghost-nested" && bad "nested Plan with live worktree should not be flagged" || ok "nested Plan with live worktree not flagged"
rm -rf "$REPO/.worktrees/auth" "$REPO/.plans/auth"

printf 'line\n%.0s' $(seq 1 60) > "$REPO/docs/notes/auth.md"   # 60 lines > cap; src/auth exists
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "docs/notes/auth.md is 60 lines" && ok "oversized Note flagged" || bad "should flag oversized Note"
# Findings ride a systemMessage (visible), not bare stderr (invisible on exit 0).
echo "$out" | grep -q '"systemMessage"' && ok "nag findings ride a systemMessage" || bad "nag findings should be a systemMessage"

echo "# orphan" > "$REPO/docs/notes/ghostarea.md"   # no src/ghostarea/
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "docs/notes/ghostarea.md has no src/ghostarea/" && ok "orphan Note flagged" || bad "should flag orphan Note"
rm -f "$REPO/docs/notes/ghostarea.md"

# Governs link: a Decision pinned to a live path is clean; a dangling path is
# flagged. src/auth exists in the seed; src/ghost/gone.ts does not.
printf '# Auth tokens\nGoverns: `src/auth`\n\nWhy rotation is 15m.\n' > "$REPO/docs/decisions/auth.md"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "docs/decisions/auth.md declares Governs" && bad "a live Governs path should not be flagged" || ok "Decision with a live Governs path not flagged"
printf '# Export format\nGoverns: src/ghost/gone.ts\n\nWhy CSV.\n' > "$REPO/docs/decisions/export.md"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "docs/decisions/export.md declares Governs: src/ghost/gone.ts, which no longer exists" && ok "Decision with a dangling Governs path flagged" || bad "should flag a dangling Governs path"
rm -f "$REPO/docs/decisions/auth.md" "$REPO/docs/decisions/export.md"

# The nag never blocks: even with findings present, no block decision is emitted.
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>/dev/null)
echo "$out" | grep -q '"decision":"block"' && bad "nag must never block" || ok "nag stays advisory (never blocks)"

echo
echo "== worktree.sh add/landable/remove =="
WSH="$PLUGIN_ROOT/scripts/worktree.sh"
(cd "$REPO" && bash "$WSH" add feature-x >/dev/null) && [ -d "$REPO/.worktrees/feature-x" ] && ok "worktree add created .worktrees/feature-x" || bad "worktree add failed"
# The worktree is the claim: a second add of the same change is "already claimed"
# (exit 4), distinct from a usage/real error (2), so a run knows to skip it.
(cd "$REPO" && bash "$WSH" add feature-x >/dev/null 2>&1); [ $? -eq 4 ] && ok "second add of a claimed change exits 4" || bad "re-add of a claimed change should exit 4"
(cd "$REPO/.worktrees/feature-x" && echo y > src_x && git add -A && git commit -qm x)
out=$(cd "$REPO" && bash "$WSH" landable) && echo "$out" | grep -q "feature-x" && ok "landable lists the ahead worktree" || bad "landable should list feature-x"
(cd "$REPO" && bash "$WSH" remove "$REPO/.worktrees/feature-x") && [ ! -d "$REPO/.worktrees/feature-x" ] && ok "worktree remove cleaned up" || bad "worktree remove failed"
out=$(cd "$REPO" && bash "$WSH" remove "/tmp/not-ours" 2>&1); [ $? -eq 3 ] || echo "$out" | grep -q "did not create it" && ok "remove refuses foreign path (exit 3)" || bad "remove should refuse foreign path"

echo
echo "== guard: durable perimeter (db/ + scripts/ defaults, .hone-durable-paths) =="
# db/ is durable by default → denied in the primary tree.
out=$(guard_write "db/migrations/0001_init.sql" "$REPO")
denied "$out" && ok "db/ denied in primary tree" || bad "db/ should be durable by default"
# ...but writable in a worktree (rule 1 is primary-tree-only; rule 2 is src/-only).
out=$(guard_write "db/migrations/0001_init.sql" "$WT")
denied "$out" && bad "db/ should be writable in a worktree" || ok "db/ writable in a worktree"
# scripts/ (the adapters) is durable by default → denied in the primary tree,
# writable in a worktree.
out=$(guard_write "scripts/typecheck.sh" "$REPO")
denied "$out" && ok "scripts/ denied in primary tree" || bad "scripts/ should be durable by default"
out=$(guard_write "scripts/typecheck.sh" "$WT")
denied "$out" && bad "scripts/ should be writable in a worktree" || ok "scripts/ writable in a worktree"
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
# The policy files themselves are protected in the primary tree: an Edit that
# widens or shrinks the perimeter is a reviewed change, not a workspace edit.
out=$(guard_write ".hone-durable-paths" "$REPO")
denied "$out" && ok "policy file denied in primary tree" || bad ".hone-durable-paths should be guard-protected"
out=$(guard_write ".hone-irreversible-paths" "$REPO")
denied "$out" && ok "irreversible-paths policy file denied in primary tree" || bad ".hone-irreversible-paths should be guard-protected"
# The proof-always marker is policy of the same kind: an agent that rewrites or
# empties it walks past the land proof gate in one step.
out=$(guard_write ".hone-proof-always" "$REPO")
denied "$out" && ok "proof-always marker denied in primary tree" || bad ".hone-proof-always should be guard-protected"

echo
echo "== nag: zero-deletion change (advisory, pre-land) =="
# The auth-login worktree: commit everything so the tree is clean on hone/auth-login,
# with a purely additive diff vs the primary branch.
(cd "$WT" && echo "new behaviour" > added.txt && git add -A && git commit -qm "feat: additive only")
out=$(cd "$WT" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "deletes nothing" && ok "purely additive pre-land change flagged" || bad "should flag a zero-deletion change on a clean hone/* branch"
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
# A branch attached to a live worktree (hone/auth-login) is active work. Check
# it was NOT flagged in the run above.
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "hone/auth-login is fully merged" && bad "branch with live worktree should not be flagged" || ok "branch with live worktree not flagged"

echo
echo "== nag: a Plan reference is not a Plan =="
# .plans/<slug>/ holds the Plan's references. A markdown one must not be counted
# as a pending Plan of its own (the sibling <slug>.md is the giveaway).
mkdir -p "$REPO/.plans/withrefs"
printf '# Plan: withrefs\n' > "$REPO/.plans/withrefs.md"
printf '| in | out |\n' > "$REPO/.plans/withrefs/cases.md"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "withrefs/cases" && bad "a reference must not be read as a Plan" || ok "markdown reference not counted as a Plan"
rm -rf "$REPO/.plans/withrefs" "$REPO/.plans/withrefs.md"

echo
echo "== nag: durable truth stranded in harness memory =="
# A pristine repo, so the memory finding is the ONLY finding: otherwise the
# leftover Plans and orphan Notes above would block under .hone-nag-enforce and
# the advisory-never-blocks assertion would pass for the wrong reason.
MEMREPO=$(mktemp -d)
git -C "$MEMREPO" init -q && git -C "$MEMREPO" symbolic-ref HEAD refs/heads/main
git -C "$MEMREPO" config user.email t@t.t; git -C "$MEMREPO" config user.name t
echo seed > "$MEMREPO/README.md"
git -C "$MEMREPO" add -A && git -C "$MEMREPO" commit -qm seed
# The harness keys its memory dir by the project's absolute path, "/" → "-".
MEMCFG="$MEMREPO/.memcfg"
MEMDIR="$MEMCFG/projects/$(cd "$MEMREPO" && pwd -P | tr '/' '-')/memory"
mkdir -p "$MEMDIR"
printf -- '---\nname: goal\nmetadata:\n  type: project\n---\n\nship it\n' > "$MEMDIR/goal.md"
printf -- '---\nname: pref\nmetadata:\n  type: user\n---\n\nplain english\n' > "$MEMDIR/pref.md"
out=$(cd "$MEMREPO" && CLAUDE_CONFIG_DIR="$MEMCFG" bash "$NAG" </dev/null 2>&1)
echo "$out" | grep -q "goal.md is a 'type: project' harness memory" && ok "project-typed memory flagged" || bad "should flag a type: project memory"
echo "$out" | grep -q "pref.md" && bad "user-typed memory should not be flagged" || ok "user-typed memory not flagged"
# Fails open: an absent memory dir yields nothing, never a false finding.
out=$(cd "$MEMREPO" && CLAUDE_CONFIG_DIR="$MEMREPO/.nonexistent" bash "$NAG" </dev/null 2>&1)
echo "$out" | grep -q "harness memory" && bad "absent memory dir should yield nothing" || ok "absent memory dir fails open"
rm -rf "$MEMREPO"

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
echo "== common: a control character never breaks a hook decision =="
# A gate's output tail carries whatever the runner printed, tabs and carriage
# returns included. A raw control character inside a JSON string is invalid, the
# harness drops the whole decision, and a blocking gate then fails OPEN.
if command -v python3 >/dev/null 2>&1; then
    payload=$'col1\tcol2\rprogress\\ "quoted"\nnext line\x0bvertical tab'
    out=$(. "$PLUGIN_ROOT/hooks/common.sh"; hone_stop_block "$payload")
    if printf '%s' "$out" | python3 -c '
import json, sys
r = json.load(sys.stdin)["reason"]
assert "col1\tcol2" in r, "tab lost"
assert "\r" in r, "carriage return lost"
assert "\x0b" not in r, "raw control character survived"
assert "next line" in r and "\"quoted\"" in r, "text mangled"
' 2>/dev/null; then
        ok "a tab, CR, and control character leave the block JSON valid"
    else
        bad "a tab or CR in a hook reason should not break the decision JSON"
    fi
    out=$(. "$PLUGIN_ROOT/hooks/common.sh"; hone_pretool_decision deny $'a\tb\rc')
    printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
        && ok "a PreToolUse decision escapes the same characters" \
        || bad "a PreToolUse decision should stay valid JSON"
else
    ok "SKIP JSON escaping test: python3 not available"
fi

echo
echo "== session-start: canonical deny rules =="
SESSION_START="$PLUGIN_ROOT/hooks/session-start.sh"
DENY_CANON="$PLUGIN_ROOT/templates/settings/deny-rules.txt"
SETTINGS="$REPO/.claude/settings.json"
mkdir -p "$REPO/.claude"
ss() { (cd "$REPO" && CLAUDE_PROJECT_DIR="$REPO" bash "$SESSION_START"); }
# Write $SETTINGS carrying every canonical rule, piped through filter $1 (a
# sed program; '' = verbatim). The output only has to satisfy the grep-based
# comparison, not a JSON parser, so a filtered-out last element's dangling
# comma is harmless.
canon_settings() {
    { echo '{"permissions":{"deny":['
      grep -vE '^[[:space:]]*(#|$)' "$DENY_CANON" | sed 's/.*/"&",/' | sed -e '$ s/,$//' -e "${1:-}"
      echo ']}}'
    } > "$SETTINGS"
}

canon_settings ''
out=$(ss)
echo "$out" | grep -q 'missing these deny rules' && bad "complete canonical set should not warn" || ok "complete canonical set: no warning"

canon_settings 's|Edit(\./|Edit(|'
out=$(ss)
echo "$out" | grep -q 'missing these deny rules' && bad "bare Edit(x) spelling should count" || ok "bare Edit(x) spelling counts"

canon_settings '\|scripts/proof\.sh|d'
out=$(ss)
if echo "$out" | grep -qF 'Edit(./scripts/proof.sh)' && ! echo "$out" | grep -qF 'Edit(./scripts/lint.sh)'; then
    ok "one missing rule named, present ones not"
else
    bad "warning should name exactly the missing rule"
fi

canon_settings 's|Edit(\./scripts/lint\.sh)|Write(./scripts/lint.sh)|'
out=$(ss)
echo "$out" | grep -qF 'Edit(./scripts/lint.sh)' && ok "inert Write spelling does not satisfy" || bad "a Write(path) rule should not satisfy the Edit requirement"

canon_settings '\|no-verify|d'
printf '{"permissions":{"deny":["Bash(git commit*--no-verify*)"]}}\n' > "$REPO/.claude/settings.local.json"
out=$(ss)
echo "$out" | grep -q 'missing these deny rules' && bad "settings.local.json should count" || ok "settings.local.json counts"
rm -f "$REPO/.claude/settings.local.json"

# The README's install block must carry the whole canonical list: it is what
# the warnings tell the human to paste from.
readme_ok=1
while IFS= read -r rule; do
    case "$rule" in ''|'#'*) continue ;; esac
    grep -qF "\"$rule\"" "$PLUGIN_ROOT/README.md" || { readme_ok=0; bad "README install block lacks $rule"; }
done < <(grep -vE '^[[:space:]]*(#|$)' "$DENY_CANON")
[ "$readme_ok" -eq 1 ] && ok "README install block carries every canonical rule"

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
