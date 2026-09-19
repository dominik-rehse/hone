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
# True if the guard output asks.
asked() { echo "$1" | grep -q '"permissionDecision":"ask"'; }

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

echo "== guard: a check config asks, in any tree =="
# The gate's lint, format, and type-check runs are only as strict as the
# config they read, so an edit there is the cheapest route from red to green
# that touches no code. Some such edits are the Plan's own work, so the guard
# asks rather than denies, in the primary tree and in a worktree alike.
for cfg in biome.json eslint.config.mjs .eslintrc.json .prettierrc .prettierignore \
           ruff.toml .ruff.toml tsconfig.json tsconfig.build.json pyrightconfig.json \
           .shellcheckrc packages/web/.eslintrc.json \
           bunfig.toml vitest.config.ts jest.config.js pytest.ini .dprint.json; do
    out=$(guard_write "$cfg" "$WT")
    asked "$out" && ok "check config asks in a worktree: $cfg" || bad "a check config should ask in a worktree: $cfg"
done
out=$(guard_write "biome.json" "$REPO")
asked "$out" && ok "check config asks in the primary tree" || bad "a check config should ask in the primary tree"
echo "$out" | grep -q 'gate' && ok "the ask names the gate as the reason" || bad "the ask should name the gate"
# A manifest that also carries tool settings stays the project's business, and
# a lookalike is not a config.
for other in package.json pyproject.toml setup.cfg src/biome.jsonx tsconfig.json.bak; do
    out=$(guard_write "$other" "$WT")
    asked "$out" && bad "not a check config, should not ask: $other" || ok "not a check config: $other"
done
# A project that lists a config in .hone-durable-paths gets the primary-tree
# deny first, because rule 1 runs before rule 1b.
printf 'biome.json\n' > "$REPO/.hone-durable-paths"
out=$(guard_write "biome.json" "$REPO")
denied "$out" && ok "a durable-listed config is denied in the primary tree, not asked" || bad "rule 1 should win over rule 1b in the primary tree"
rm "$REPO/.hone-durable-paths"

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

echo "== guard: docs/spikes/ is writable in the primary tree, whatever the type =="
# A spike is dated, frozen history written outside the loop, and it usually
# precedes any Plan. Everything one spike leaves behind lives here, of any
# type: the note, the probe that produced it, a mockup, a captured payload. So
# it is the one path under docs/ the primary-tree rule lets through, exactly as
# it lets .plans/ through.
for f in 2026-08-19-sse-backpressure.md \
         2026-08-19-sse-backpressure.html \
         2026-08-19-sse-backpressure.ts \
         2026-08-19-sse-backpressure/probe.sh \
         2026-08-19-sse-backpressure/capture.json; do
    out=$(guard_write "docs/spikes/$f" "$REPO")
    denied "$out" && bad "docs/spikes/$f should be writable in the primary tree" || ok "docs/spikes/$f allowed"
done
out=$(guard_write "docs/notes/auth.md" "$REPO")
denied "$out" && ok "docs/ outside spikes/ still denied in the primary tree" || bad "the rest of docs/ must stay denied in the primary tree"

echo "== guard: docs/open-questions.md is writable in the primary tree =="
# The plan skill records a plan-time open question in this ledger, and
# /hone:plan runs in the primary tree. So the guard leaves this one file
# open, exactly as it leaves docs/spikes/.
out=$(guard_write "docs/open-questions.md" "$REPO")
denied "$out" && bad "docs/open-questions.md should be writable in the primary tree" || ok "docs/open-questions.md allowed"
# The exemption is the exact file, never a lookalike.
out=$(guard_write "docs/open-questions-draft.md" "$REPO")
denied "$out" && ok "a lookalike docs file is still denied" || bad "only the exact ledger file is exempt"
# .hone-durable-paths re-protects it for a project that wants that.
printf 'docs/open-questions.md\n' > "$REPO/.hone-durable-paths"
out=$(guard_write "docs/open-questions.md" "$REPO")
denied "$out" && ok ".hone-durable-paths re-protects the ledger" || bad ".hone-durable-paths should re-protect the ledger"
rm "$REPO/.hone-durable-paths"

echo "== guard: .hone-off disables it =="
touch "$REPO/.hone-off"
out=$(guard_write "src/auth/login.ts" "$REPO")
denied "$out" && bad ".hone-off should disable the guard" || ok ".hone-off disables the guard"
rm -f "$REPO/.hone-off"

echo "== bash-guard: tamper resistance =="
bg() { echo "{\"tool_input\":{\"command\":\"$1\"}}" | (cd "$REPO" && bash "$BASH_GUARD"); }
# The same, plus the top-level `cwd` field the harness sets: $2 = the directory
# the SHELL stands in. The hook process still runs in the primary tree, which is
# what Claude Code does after Claude cds into a worktree.
bgcwd() { echo "{\"cwd\":\"$2\",\"tool_input\":{\"command\":\"$1\"}}" | (cd "$REPO" && bash "$BASH_GUARD"); }
bgwt_early() { echo "{\"tool_input\":{\"command\":\"$1\"}}" | (cd "$WT" && bash "$BASH_GUARD"); }
echo "$(bg 'git commit --no-verify -m x')" | grep -q '"deny"' && ok "--no-verify denied" || bad "--no-verify should be denied"
# Git reads a config key in any case, so the lowercase spelling disables the
# hooks exactly as the camel-case one does. The scan is case-insensitive.
echo "$(bg 'git -c core.hookspath=/dev/null commit -m x')" | grep -q '"deny"' && ok "lowercase core.hookspath denied" || bad "core.hookspath should be denied in any case"
echo "$(bg 'git config core.HooksPath /tmp/h')" | grep -q '"deny"' && ok "camel-case core.HooksPath denied" || bad "core.HooksPath should be denied"
# A commit message and a sign-off text are prose. The rules read the command
# with that prose removed, so a message that documents a token is not the act.
# The flag outside the message still denies, wherever it sits.
echo "$(bg 'git commit -m x --no-verify')" | grep -q '"deny"' && ok "--no-verify after the message denied" || bad "a flag after -m should still deny"
echo "$(bg 'git commit -m \"docs: explain why --no-verify is denied\"')" | grep -q 'permissionDecision' && bad "a commit message naming --no-verify is prose" || ok "--no-verify inside a commit message passes"
echo "$(bg 'git commit --message=\"see core.hooksPath\"')" | grep -q 'permissionDecision' && bad "a --message= value is prose" || ok "core.hooksPath inside --message= passes"
echo "$(bg 'git commit -am \"chore: bun add dprint, then sed -i on scripts/lint.sh\"')" | grep -q 'permissionDecision' && bad "a message naming a writer and an adapter is prose" || ok "a writer and an adapter inside a message pass"
echo "$(bg 'git commit -m \"$(cat <<'"'"'EOF'"'"'\nfix: x\n\nthe guard denies core.hooksPath and git reset --hard\nEOF\n)\"')" | grep -q 'permissionDecision' && bad "a heredoc message body is prose" || ok "a heredoc message body passes"
echo "$(bg 'bash scripts/worktree.sh grant db-drop drops the table, git reset --hard cannot undo it')" | grep -q 'permissionDecision' && bad "a grant reason is prose" || ok "a HEAD-move named in a grant reason passes"
echo "$(bg 'git commit -m x && touch .hone-off')" | grep -q '"deny"' && ok "the act after a message still denies" || bad "stripping the message must not hide the act"
# The strip never blanks a quoted string elsewhere: a quoted path is a target.
echo "$(bg 'sed -i s/x/y/ \"scripts/lint.sh\"')" | grep -q '"ask"' && ok "a quoted adapter target still asks" || bad "a quoted path is a real target"
# The check configs join the protected set for the shell route, in any tree.
echo "$(bg 'sed -i s/x/y/ biome.json')" | grep -q '"ask"' && ok "editing biome.json escalated" || bad "editing a check config should ask"
echo "$(bg 'echo {} > .eslintrc.json')" | grep -q '"ask"' && ok "a redirect into .eslintrc.json escalated" || bad "a redirect into a check config should ask"
echo "$(bg 'rm packages/web/tsconfig.json')" | grep -q '"ask"' && ok "removing a nested tsconfig.json escalated" || bad "a nested check config should ask"
echo "$(bgwt_early 'sed -i s/x/y/ ruff.toml')" | grep -q '"ask"' && ok "editing ruff.toml inside a worktree escalated" || bad "a check config should ask in a worktree too"
echo "$(bg 'cat biome.json')" | grep -q 'permissionDecision' && bad "reading a check config should pass" || ok "reading a check config passes"
echo "$(bg 'touch .hone-off')" | grep -q '"deny"' && ok "touch .hone-off denied" || bad "touch .hone-off should be denied"
echo "$(bg 'sed -i s/x/y/ scripts/run-tests.sh')" | grep -q '"ask"' && ok "editing run-tests.sh escalated" || bad "editing adapter should ask"
echo "$(bg 'ls -la')" | grep -q 'permissionDecision' && bad "benign command should pass silently" || ok "benign command passes"
# The helpers are the only route into .hone-grant/ and .hone-proof/. They are
# allowed to the agent; every raw write past them stays denied, because the
# stamp, the commit binding, and the placeholder check live in the helper.
echo "$(bg 'echo signed > .hone-proof/ui-flow')" | grep -q '"deny"' && ok "writing a proof sign-off denied" || bad "writing .hone-proof/ should be denied"
echo "$(bg 'mkdir -p .hone-grant && touch .hone-grant/db-drop')" | grep -q '"deny"' && ok "creating a grant denied" || bad "creating .hone-grant/<change> should be denied"
echo "$(bg 'bash scripts/worktree.sh grant db-drop reason')" | grep -q 'permissionDecision' && bad "the grant helper should pass" || ok "grant helper allowed"
# The proof sign-off is the human's act: the attest helper is denied to the
# agent whatever its text says, with the deny that tells it to hand the output
# over. The grant helper stays the agent's to call. A mention of the word
# inside a commit message stays prose.
out=$(bg 'bash scripts/worktree.sh attest db-drop ran-it')
echo "$out" | grep -q '"deny"' && ok "attest helper denied to the agent" || bad "the attest helper should be denied"
echo "$out" | grep -q "the human's act" && ok "the attest deny names the human" || bad "the attest deny should say whose act it is"
echo "$(bg 'bash \"$CLAUDE_PLUGIN_ROOT/scripts/worktree.sh\" attest db-drop ran-it')" | grep -q '"deny"' && ok "attest denied through a quoted plugin path" || bad "attest through a quoted path should be denied"
echo "$(bg 'git commit -m attest later')" | grep -q 'permissionDecision' && bad "attest inside a commit message is prose" || ok "attest named in a commit message passes"
echo "$(bg 'bash scripts/worktree.sh status')" | grep -q 'permissionDecision' && bad "status should pass" || ok "worktree.sh status passes"
echo "$(bg 'cat .hone-grant/db-drop')" | grep -q 'permissionDecision' && bad "reading a grant should pass silently" || ok "reading a grant allowed"
# Only CREATING the off marker is sabotage. A read-only existence check names
# the marker too, and denying that one cost a real session its diagnosis.
echo "$(bg 'ls -la .hone-off || echo no .hone-off marker present')" | grep -q 'permissionDecision' && bad "an existence check for .hone-off should pass" || ok "reading .hone-off passes"
echo "$(bg 'cat .hone-off')" | grep -q 'permissionDecision' && bad "reading .hone-off should pass" || ok "cat .hone-off passes"
echo "$(bg 'echo x > .hone-off')" | grep -q '"deny"' && ok "a redirect into .hone-off denied" || bad "echo into .hone-off should be denied"
echo "$(bg 'printf x >> .hone-off')" | grep -q '"deny"' && ok "an append into .hone-off denied" || bad "printf into .hone-off should be denied"
echo "$(bg 'echo x > /tmp/repo/.hone-off')" | grep -q '"deny"' && ok "a redirect into a path ending in .hone-off denied" || bad "a pathful redirect should be denied"
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
# .hone-review-always is the same class: deleting it is the cheapest way to make
# a docs-only change skip its review.
# .hone-shared decides where the team lands, and deleting it is the cheapest
# way past a push the host refused.
echo "$(bg 'rm .hone-shared')" | grep -q '"ask"' && ok "removing .hone-shared escalated" || bad "removing the shared marker should ask"
echo "$(bg 'rm .hone-review-always')" | grep -q '"ask"' && ok "removing .hone-review-always escalated" || bad "removing the review-always list should ask"
# messages.sh carries hone's own prose, and it belongs to the same plugin-side
# class as the other hooks the pattern already lists.
echo "$(bg 'sed -i s/x/y/ hooks/messages.sh')" | grep -q '"ask"' && ok "editing hooks/messages.sh escalated" || bad "editing a plugin hook file should ask"
# A redirect binds to the path right after it. An angle bracket inside a quoted
# message is prose, and the sign-off text is prose the helper asks for. Reading
# the two alike escalated the one helper the agent is meant to call by itself.
echo "$(bg 'bash scripts/worktree.sh grant ui-flow ran PROOF_ROOT=<worktree> bash scripts/proof.sh ui-flow, exit 0')" | grep -q 'permissionDecision' && bad "prose naming an adapter after an angle bracket should pass" || ok "an angle bracket in a grant message passes"
echo "$(bg 'git commit -m ran with PROOF_ROOT=<worktree> and then scripts/lint.sh')" | grep -q 'permissionDecision' && bad "a commit message is prose, not a write" || ok "an angle bracket in a commit message passes"
# A real redirect into the same file still escalates, whatever precedes it.
echo "$(bg 'echo x > scripts/lint.sh')" | grep -q '"ask"' && ok "a redirect into an adapter escalated" || bad "a redirect into scripts/lint.sh should ask"
echo "$(bg 'cat template >> hooks/gate.sh')" | grep -q '"ask"' && ok "an append into a hook escalated" || bad "an append into hooks/gate.sh should ask"
echo "$(bg 'cat x > /home/u/repo/scripts/proof.sh')" | grep -q '"ask"' && ok "a pathful redirect into an adapter escalated" || bad "a pathful redirect should ask"
# A HEAD-move in the primary tree races other sessions → ask; the same op inside
# a linked worktree is isolated → silent.
echo "$(bg 'git checkout some-commit')" | grep -q '"ask"' && ok "git checkout in primary tree escalated" || bad "checkout in primary should ask"
echo "$(bg 'git stash push -- IDEAS.md')" | grep -q '"ask"' && ok "git stash in primary tree escalated" || bad "stash in primary should ask"
echo "$(bg 'git reset --hard HEAD^')" | grep -q '"ask"' && ok "git reset --hard in primary tree escalated" || bad "hard reset in primary should ask"
# `git stash list` and `git stash show` only read the stash. Escalating them
# stopped unattended runs on a read. Every other stash form still asks, judged
# per segment, and an unknown subcommand fails closed.
echo "$(bg 'git stash list')" | grep -q 'permissionDecision' && bad "git stash list only reads" || ok "git stash list passes"
echo "$(bg 'git stash show -p stash@{0}')" | grep -q 'permissionDecision' && bad "git stash show only reads" || ok "git stash show passes"
echo "$(bg 'git stash')" | grep -q '"ask"' && ok "a bare git stash escalated" || bad "a bare git stash pushes, so it should ask"
echo "$(bg 'git stash -u')" | grep -q '"ask"' && ok "a flags-first git stash escalated" || bad "git stash -u pushes, so it should ask"
echo "$(bg 'git stash drop')" | grep -q '"ask"' && ok "git stash drop escalated" || bad "git stash drop mutates, so it should ask"
echo "$(bg 'git stash list; git stash pop')" | grep -q '"ask"' && ok "a read does not excuse a pop in the next segment" || bad "a pop after a list should still ask"
bgwt() { echo "{\"tool_input\":{\"command\":\"$1\"}}" | (cd "$WT" && bash "$BASH_GUARD"); }
echo "$(bgwt 'git checkout some-commit')" | grep -q '"ask"' && bad "HEAD-move inside a worktree should not ask" || ok "HEAD-move allowed inside a worktree"

# Rule 3 also covers a move of the PRIMARY BRANCH itself, not only of HEAD.
# The primary branch is a merge target that `worktree.sh land` moves, under the
# lock and with the post-merge suite. A run of the ImpossibleBench probe made a
# worktree by hand and fast-forwarded the branch, with no review and no land
# gate, and no rule named `git merge`.
echo "$(bg 'git merge --ff-only hone/auth-login')" | grep -q '"ask"' && ok "a fast-forward merge in the primary tree escalated" || bad "git merge --ff-only should ask"
echo "$(bg 'git merge --no-ff hone/auth-login -m landed')" | grep -q '"ask"' && ok "a --no-ff merge in the primary tree escalated" || bad "git merge --no-ff should ask"
echo "$(bg 'git push . hone/auth-login:main')" | grep -q '"ask"' && ok "a push into the repo itself escalated" || bad "git push . branch:main should ask"
echo "$(bg 'git branch -f main hone/auth-login')" | grep -q '"ask"' && ok "a forced branch move escalated" || bad "git branch -f main should ask"
echo "$(bg 'git update-ref refs/heads/main hone/auth-login')" | grep -q '"ask"' && ok "a raw ref update escalated" || bad "git update-ref refs/heads/main should ask"
echo "$(bg 'git cherry-pick hone/auth-login')" | grep -q '"ask"' && ok "a cherry-pick in the primary tree escalated" || bad "git cherry-pick in primary should ask"
echo "$(bg 'git rebase hone/auth-login')" | grep -q '"ask"' && ok "a rebase in the primary tree escalated" || bad "git rebase in primary should ask"
# --soft and --mixed move the branch too. Only --hard/--merge/--keep asked.
echo "$(bg 'git reset --soft HEAD^')" | grep -q '"ask"' && ok "a soft reset in the primary tree escalated" || bad "git reset --soft moves the branch, so it should ask"
# The tree decision has to fail closed for real. `git -C <primary>` and a
# command that cds BACK to the primary tree both write there, and the shell
# that issued the probe's merge stood in a worktree at the time.
echo "$(bgcwd "git -C $REPO merge --ff-only hone/auth-login" "$WT")" | grep -q '"ask"' && ok "git -C into the primary tree escalated" || bad "git -C <primary> should ask from a worktree shell"
echo "$(bgcwd "cd $WT && true && cd $REPO && git merge --ff-only hone/auth-login" "$WT")" | grep -q '"ask"' && ok "a cd back to the primary tree escalated from a worktree shell" || bad "two cds ending in the primary tree should ask"
echo "$(bg "cd $WT && true && cd $REPO && git merge --ff-only hone/auth-login")" | grep -q '"ask"' && ok "a cd back to the primary tree escalated from a primary shell" || bad "two cds ending in the primary tree should ask"

# The negative half. Without it the rule could pass by asking about everything.
# A read of the history, a merge base, and prose that names a merge are not
# moves, and the sanctioned route must never escalate.
echo "$(bg 'git log --merges --oneline -20')" | grep -q 'permissionDecision' && bad "git log --merges only reads" || ok "git log --merges passes"
echo "$(bg 'git merge-base main hone/auth-login')" | grep -q 'permissionDecision' && bad "git merge-base only reads" || ok "git merge-base passes"
echo "$(bg 'git commit -m fix:-land-merges---no-ff-so-never-merge-by-hand')" | grep -q 'permissionDecision' && bad "a commit message is prose, not a merge" || ok "a merge named in a commit message passes"
echo "$(bg 'bash scripts/worktree.sh land auth-login')" | grep -q 'permissionDecision' && bad "land is the sanctioned route" || ok "worktree.sh land passes"
echo "$(bg 'git push origin hone/auth-login')" | grep -q 'permissionDecision' && bad "pushing the change branch moves no primary branch" || ok "a push of the change branch passes"
# Every one of these is worktree work when the shell stands in a worktree.
echo "$(bgwt 'git merge --ff-only main')" | grep -q 'permissionDecision' && bad "a merge inside a worktree is isolated" || ok "a merge inside a worktree passes"
echo "$(bgwt 'git rebase main')" | grep -q 'permissionDecision' && bad "a rebase inside a worktree is isolated" || ok "a rebase inside a worktree passes"
echo "$(bgwt 'git cherry-pick some-commit')" | grep -q 'permissionDecision' && bad "a cherry-pick inside a worktree is isolated" || ok "a cherry-pick inside a worktree passes"
echo "$(bgcwd 'git merge --ff-only main' "$WT")" | grep -q 'permissionDecision' && bad "a persisted cd into a worktree is worktree work" || ok "a merge in the worktree shell passes"

# `git checkout -- <paths>` restores files and moves no HEAD, so it passes even
# in the primary tree. It is how the operator undoes a bad edit there.
echo "$(bg 'git checkout -- bun.lock package.json')" | grep -q 'permissionDecision' && bad "a pathspec restore moves no HEAD" || ok "git checkout -- <paths> passes"
echo "$(bg 'git checkout HEAD -- src/auth/login.ts')" | grep -q 'permissionDecision' && bad "a ref plus pathspec restore moves no HEAD" || ok "git checkout <ref> -- <paths> passes"
echo "$(bg 'git checkout -- bun.lock && bun install')" | grep -q 'permissionDecision' && bad "restore plus sync install moves no HEAD" || ok "restore plus a sync install passes"
# A branch-like checkout still asks, and a restore later in the line does not
# excuse a real HEAD move earlier in it.
echo "$(bg 'git checkout -b hone/x')" | grep -q '"ask"' && ok "git checkout -b escalated" || bad "checkout -b should ask"
echo "$(bg 'git checkout main && git checkout -- src/auth/login.ts')" | grep -q '"ask"' && ok "a HEAD move in an earlier segment still escalates" || bad "a later restore should not excuse a HEAD move"
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
# A subshell wraps the same cd idiom. The wrapped and unwrapped forms must
# read as the same command.
echo "$(bg "(cd $WT && bun add -d dprint@latest)")" | grep -q 'permissionDecision' && bad "a subshell cd into a worktree is worktree work" || ok "a subshell cd into a worktree passes"
echo "$(bg "(cd $REPO && bun add -d dprint@latest)")" | grep -q '"ask"' && ok "a subshell cd back to the primary tree still asks" || bad "a subshell cd to the primary tree should ask"
# The loop cds into its worktree ONCE and then works there, so most commands
# carry no cd at all. The harness reports that shell directory in the top-level
# `cwd` field, and the hook has to read it: the hook process itself never
# leaves the primary tree.
echo "$(bgcwd 'bunx dprint fmt' "$WT")" | grep -q 'permissionDecision' && bad "a bare fmt in the worktree shell is worktree work" || ok "a persisted cd into a worktree passes rule 4b"
echo "$(bgcwd 'bun add -d dprint@latest' "$WT")" | grep -q 'permissionDecision' && bad "an install in the worktree shell is worktree work" || ok "a persisted cd into a worktree passes rule 4"
echo "$(bgcwd 'git switch main' "$WT")" | grep -q 'permissionDecision' && bad "a branch switch in the worktree shell is worktree work" || ok "a persisted cd into a worktree passes rule 3"
# The same field names the primary tree just as often, and nothing changes then.
echo "$(bgcwd 'bunx dprint fmt' "$REPO")" | grep -q '"ask"' && ok "a bare fmt in the primary-tree shell still asks" || bad "the primary tree keeps its rules"
echo "$(bgcwd 'bun add -d dprint@latest' /nonexistent-tree)" | grep -q '"ask"' && ok "an unusable cwd field falls back to the hook's tree" || bad "a missing cwd directory should fall back"
# A leading cd moves the shell once more, and a relative target resolves
# against the shell's directory rather than the hook's.
echo "$(bgcwd 'cd auth-login && bun add -d dprint@latest' "$REPO/.worktrees")" | grep -q 'permissionDecision' && bad "a relative cd resolves against the shell cwd" || ok "a relative cd resolves against the shell cwd"
# A write-mode formatter passes when it is scoped to non-durable relative
# paths, the same perimeter the file tools apply. The Plan is the case that
# matters: /hone:plan writes it in the primary tree, and the lint gate wants
# it formatted before its commit.
echo "$(bg 'bunx dprint fmt .plans/auth-login.md')" | grep -q 'permissionDecision' && bad "a formatter scoped to .plans/ should pass" || ok "a formatter scoped to .plans/ passes"
echo "$(bg 'bunx dprint fmt .plans/auth-login.md && git add .plans/auth-login.md')" | grep -q 'permissionDecision' && bad "the scoped fmt-then-commit idiom should pass" || ok "the scoped fmt-then-commit idiom passes"
# Everything unscoped or aimed at a durable path keeps the ask.
echo "$(bg 'bunx dprint fmt')" | grep -q '"ask"' && ok "a bare formatter run escalated" || bad "a bare fmt formats docs/, so it should ask"
echo "$(bg 'bunx dprint fmt docs/notes/auth.md')" | grep -q '"ask"' && ok "a formatter aimed at docs/ escalated" || bad "a durable path should ask"
echo "$(bg 'bunx dprint fmt .plans/../docs/x.md')" | grep -q '"ask"' && ok "a traversal out of .plans/ escalated" || bad "a .. traversal should fail closed"
echo "$(bg 'bunx dprint fmt --config other.json .plans/x.md')" | grep -q '"ask"' && ok "a config swap escalated" || bad "a non-write-mode flag should fail closed"
echo "$(bg 'bunx biome check --write src/auth/login.ts')" | grep -q '"ask"' && ok "a write-mode formatter on src/ escalated" || bad "biome --write on src/ should ask"
# Each rule prints its own remedy. A formatter can be scoped, and the reader
# has to learn that from the ask itself. A package manager cannot, so it keeps
# the worktree message.
echo "$(bg 'bunx dprint fmt')" | grep -q 'name the paths' && ok "the formatter ask offers scoping" || bad "the formatter ask should name scoping as the remedy"
echo "$(bg 'bun add -d dprint@latest')" | grep -q 'run it in a worktree' && ok "the package-manager ask keeps the worktree remedy" || bad "rule 4 should keep msg_bashguard_self_writer"

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

echo "== gate: the full tier runs once per change branch =="
# An adapter that records every invocation, so a run the gate skipped is
# countable. The record lives inside .git, so it never dirties the tree.
RUNS="$REPO/.git/adapter-runs"
RECEIPT="$REPO/.git/hone-gate-green"
: > "$RUNS"
cat > "$REPO/scripts/run-tests.sh" <<EOF
#!/bin/bash
echo "\${1:-}" >> "$RUNS"
exit 0
EOF
(cd "$REPO" && git add -A && git commit -qm "counting adapter")
TREE=$(git -C "$REPO" rev-parse 'HEAD^{tree}')
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
[ "$(wc -l < "$RUNS")" -eq 1 ] && ok "the first Stop on a change branch runs the full suite" || bad "the first Stop should run the full suite"
echo "$out" | grep -q '"systemMessage":"hone gate: green (tests (--all))"' && ok "the full run emits the green receipt" || bad "the full run should emit the green receipt"
grep -q "hone/verify-tier" "$RECEIPT" && ok "a green full run records the branch" || bad "a green full run should record the branch"
grep -q "$TREE" "$RECEIPT" && ok "a green full run records the verified tree" || bad "a green full run should record the tree"

# Same tree again: the answer cannot differ, so the suite must not run.
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
[ "$(wc -l < "$RUNS")" -eq 1 ] && ok "an unchanged tree skips the full suite" || bad "an unchanged tree should skip the full suite"
echo "$out" | grep -q 'already passed on this branch' && ok "the skip prints its own receipt" || bad "the skip should print a receipt, not stay silent"
echo "$out" | grep -q '"decision":"block"' && bad "a skip must not block the stop" || ok "the skip does not block the stop"

# A later commit on the SAME branch skips too. One early warning per change is
# the whole value of the backstop, and land re-runs --all after the merge.
echo "// more" >> "$REPO/src/auth/login.ts"
(cd "$REPO" && git add -A && git commit -qm "durable change")
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
[ "$(wc -l < "$RUNS")" -eq 1 ] && ok "a later commit on the same branch skips the full suite" || bad "a later commit on the same branch should skip"
grep -q "$TREE" "$RECEIPT" && ok "the receipt keeps the tree its run verified" || bad "a skip should leave the receipt alone"

# Another change branch is another change, so it earns its own run.
git -C "$REPO" checkout -q -b hone/second-change
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
[ "$(wc -l < "$RUNS")" -eq 2 ] && ok "another change branch runs the full suite" || bad "another change branch should run the full suite"
grep -q "hone/second-change" "$RECEIPT" && ok "the receipt follows the new branch" || bad "the receipt should hold the new branch"
git -C "$REPO" checkout -q hone/verify-tier

# Uncommitted durable dirt runs the unit tier, which no receipt covers.
echo "// dirt" >> "$REPO/src/auth/login.ts"
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
[ "$(tail -n 1 "$RUNS")" = "--unit" ] && ok "the skip never applies to the unit tier" || bad "the unit tier should run on a dirty tree"
grep -q "hone/second-change" "$RECEIPT" && ok "the unit tier leaves the receipt alone" || bad "the unit tier should not write a receipt"
git -C "$REPO" checkout -q -- src/auth/login.ts

# A receipt an older plugin version wrote is a miss: a gate with new steps must
# not trust what an older gate verified. The gate before this one recorded no
# branch, so its two-field line misses as well.
RUNS_BEFORE=$(wc -l < "$RUNS")
printf '0.0.0-old %s\n' "$TREE" > "$RECEIPT"
out=$(cd "$REPO" && echo '{}' | bash "$GATE")
[ "$(wc -l < "$RUNS")" -eq $((RUNS_BEFORE + 1)) ] && ok "a receipt from another version runs the suite again" || bad "a version mismatch should re-run the suite"

echo "== gate: the block cap lets a turn end after N identical failures =="
# A suite that cannot go green (a test that contradicts its spec) used to block
# every turn end until the harness cut the session, and the run then had no
# turn in which to report. The gate now caps itself at HONE_GATE_BLOCK_CAP
# identical failures. Identical means the same step, the same exit code, and
# the same output once every run of digits is collapsed.
CAPTAIL="$REPO/.git/cap-tail"
cat > "$REPO/scripts/run-tests.sh" <<EOF
#!/bin/bash
cat "$CAPTAIL"
exit 1
EOF
(cd "$REPO" && git add -A && git commit -qm "red adapter with a fixed tail")
BLOCKS="$REPO/.git/hone-gate-blocks"
# Dirty src keeps every run on the unit tier, so no receipt and no lock apply.
echo "// cap" >> "$REPO/src/auth/login.ts"
# The cap ends in two steps: the Nth identical failure blocks once more and
# asks for the final report, and only the next one lets the turn end. So the
# last turn holds a report instead of whatever the run was saying.
stop() { (cd "$REPO" && printf '{"session_id":"%s"}' "$1" | bash "$GATE"); }
capped()  { echo "$1" | grep -q 'in a row with the same output, so the gate let this turn end'; }
asked()   { echo "$1" | grep -q 'write your final report in this turn'; }

printf 'not ok 1 fee inside the grace period\n  duration_ms 12.5\n' > "$CAPTAIL"
rm -f "$BLOCKS"
out=$(stop s1); blocked "$out" && ok "the first identical failure blocks" || bad "the first failure should block"
asked "$out" && bad "the first block must not announce the cap" || ok "the first block says nothing of the cap"
out=$(stop s1); blocked "$out" && ok "the second identical failure blocks" || bad "the second failure should block"
asked "$out" && bad "the second block must not announce the cap" || ok "the second block says nothing of the cap"
# Same failure, a different duration. A runner prints one on every line, and it
# must not read as progress.
printf 'not ok 1 fee inside the grace period\n  duration_ms 9.113\n' > "$CAPTAIL"
out=$(stop s1)
blocked "$out" && ok "the third identical failure still blocks" || bad "the report request should block"
asked "$out" && ok "the third block asks for the final report in this turn" || bad "the third block should ask for the report"
echo "$out" | grep -qE 'hone-off|--no-verify|hooksPath' && bad "the report request must name no way to switch hone off" || ok "the report request names no switch"
# The turn after the report request ends, and the person gets the line.
out=$(stop s1)
blocked "$out" && bad "a changed duration should not reset the cap" || ok "a changed duration is the same failure, so the cap fires"
capped "$out" && ok "the cap prints its line for the person" || bad "the cap should print a line naming the repeat"
echo "$out" | grep -q 'tests (--unit)' && ok "the cap names the step that failed" || bad "the cap should name the step"
echo "$out" | grep -q 'hone-off' && bad "the cap must not offer the off switch" || ok "the cap offers no switch and no marker"

# A failure that differs in the name of the failing test is other work, so the
# count starts over and the gate blocks again.
rm -f "$BLOCKS"
printf 'not ok 1 fee inside the grace period\n  duration_ms 12.5\n' > "$CAPTAIL"
out=$(stop s2); blocked "$out" || bad "the first failure of a new session should block"
printf 'not ok 1 fee after the grace period\n  duration_ms 12.5\n' > "$CAPTAIL"
out=$(stop s2); blocked "$out" || bad "a different failure should block"
out=$(stop s2)
blocked "$out" && ok "a changed test name resets the count" || bad "a changed failing test should reset the count"
asked "$out" && bad "a reset count must not reach the report request" || ok "a reset count starts the streak over"

# Real work after the report request resets it too: the run that changes what
# the suite prints gets its ordinary blocks back.
rm -f "$BLOCKS"
printf 'not ok 1 fee inside the grace period\n' > "$CAPTAIL"
out=$(stop s7); out=$(stop s7); out=$(stop s7)
asked "$out" || bad "the third identical failure should ask for the report"
printf 'not ok 1 fee on the fourth day\n' > "$CAPTAIL"
out=$(stop s7)
blocked "$out" && ok "a failure that moved after the report request blocks again" || bad "moved work should block again"
asked "$out" && bad "the request must not repeat on a new failure" || ok "the new streak starts at an ordinary block"

# A green turn ends the streak, so the next red failure starts at one again.
rm -f "$BLOCKS"
printf 'not ok 1 fee inside the grace period\n' > "$CAPTAIL"
out=$(stop s3); blocked "$out" || bad "the streak should start with a block"
out=$(stop s3); blocked "$out" || bad "the streak should hold at two"
cat > "$REPO/scripts/run-tests.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
out=$(stop s3); blocked "$out" && bad "a green suite must not block" || ok "the green run passes"
[ -f "$BLOCKS" ] && bad "a green run should clear the counter" || ok "a green run clears the counter"
cat > "$REPO/scripts/run-tests.sh" <<EOF
#!/bin/bash
cat "$CAPTAIL"
exit 1
EOF
out=$(stop s3); blocked "$out" && ok "after a green run the same failure blocks again" || bad "the count should start over after green"

# The count belongs to one session. Another session inherits nothing.
rm -f "$BLOCKS"
out=$(stop s4); blocked "$out" || bad "session s4 should block once"
out=$(stop s4); blocked "$out" || bad "session s4 should block twice"
out=$(stop s5)
blocked "$out" || bad "session s5 should block"
asked "$out" && bad "a new session should not inherit a count" || ok "another session starts its count at zero"

# The tunable moves both steps.
stop5() { (cd "$REPO" && printf '{"session_id":"s6"}' | HONE_GATE_BLOCK_CAP=5 bash "$GATE"); }
rm -f "$BLOCKS"
for _ in 1 2 3 4; do out=$(stop5); done
blocked "$out" || bad "a raised cap should still block the fourth identical failure"
asked "$out" && bad "HONE_GATE_BLOCK_CAP=5 should not ask on the fourth" || ok "HONE_GATE_BLOCK_CAP=5 holds its ordinary blocks to four"
out=$(stop5)
asked "$out" && ok "HONE_GATE_BLOCK_CAP=5 asks for the report on the fifth" || bad "a raised cap should ask on the fifth"
out=$(stop5)
capped "$out" && ok "HONE_GATE_BLOCK_CAP=5 caps on the sixth" || bad "a raised cap should fire after its report request"
rm -f "$BLOCKS" "$CAPTAIL"
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

# Evidence 2: a surviving hone/<change> branch that carried a commit of its
# own into the primary branch. The fold-in message is not land's, so evidence
# 1 cannot fire and this case tests evidence 2 alone.
echo "# Plan" > "$REPO/.plans/ghost2.md"
git -C "$REPO" checkout -q -b hone/ghost2
git -C "$REPO" commit -q --allow-empty -m "feat(ghost2): a commit of its own"
git -C "$REPO" checkout -q -
git -C "$REPO" merge -q --no-ff -m "chore: fold ghost2 in" hone/ghost2
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q ".plans/ghost2.md survived its landing" && ok "Plan with a merged branch of its own flagged" || bad "should flag Plan whose merged branch survives"
git -C "$REPO" branch -D hone/ghost2 >/dev/null 2>&1
rm -f "$REPO/.plans/ghost2.md"

# A hone/<change> branch that carried no commit of its own is no evidence of
# a landing. git calls it merged, because it points at a commit the primary
# branch already has, and a branch is always merged into itself. The nag read
# that as a landing and told a run to delete the Plan it was still executing
# (2026-09-19 probe). The worktree is where it hit, so test there first.
# This fixture predates setup.sh's current .gitignore and still ignores
# .plans/, so force the Plan into the commit. A linked worktree checks out
# what is tracked, and the run reads its Plan there.
echo "# Plan" > "$REPO/.plans/ghost3.md"
(cd "$REPO" && git add -f .plans/ghost3.md && git commit -qm "chore(plan): ghost3")
WT_G=$(cd "$REPO" && bash "$PLUGIN_ROOT/scripts/worktree.sh" add ghost3 2>&1 | tail -1)
if [ -n "$WT_G" ] && [ -d "$WT_G" ]; then
    out=$(cd "$WT_G" && echo '{}' | bash "$NAG" 2>&1)
    echo "$out" | grep -q "ghost3.md survived its landing" && bad "a run's own branch is not evidence of its landing" || ok "the run's own branch is no evidence inside its worktree"
    (cd "$REPO" && bash "$PLUGIN_ROOT/scripts/worktree.sh" remove "$WT_G" >/dev/null 2>&1)
else
    bad "could not make a worktree for the nag's branch-evidence test: $WT_G"
fi
(cd "$REPO" && git rm -q --cached .plans/ghost3.md && git commit -qm "chore: untrack ghost3 plan")
rm -f "$REPO/.plans/ghost3.md"

# The same branch with no worktree, seen from the primary tree. `remove`
# retires a merged branch, so make this one directly.
echo "# Plan" > "$REPO/.plans/ghost4.md"
git -C "$REPO" branch hone/ghost4 HEAD
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q ".plans/ghost4.md survived its landing" && bad "a branch with no commit of its own is not a landing" || ok "a fresh branch is no evidence of a landing"
echo "$out" | grep -q "Plan(s) pending run" && ok "such a Plan counts as pending" || bad "a Plan with no landing should count as pending"
git -C "$REPO" branch -D hone/ghost4 >/dev/null 2>&1
rm -f "$REPO/.plans/ghost4.md"

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

# Relative markdown link: a resolving target is clean, and a dangling one is
# flagged. URLs and #anchors are not files, so they never flag. The
# docs/notes/auth.md fixture from above still exists and anchors the clean case.
printf '# Auth tokens\nSee [the note](../notes/auth.md), [the spec](https://example.org/x), [above](#why).\n' > "$REPO/docs/decisions/auth.md"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "docs/decisions/auth.md links to" && bad "a resolving link should not be flagged" || ok "Decision with resolving/URL/anchor links not flagged"
printf '# Export format\nSee [the old spike](../spikes/2024-01-01-gone.md).\n' > "$REPO/docs/decisions/export.md"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "docs/decisions/export.md links to ../spikes/2024-01-01-gone.md, which does not resolve" && ok "Decision with a dangling relative link flagged" || bad "should flag a dangling relative link"
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
# The refusal says what the claim holds, so a stopped run can hand the person
# one action. A file that changed in the last 30 minutes means a run at work.
out=$(cd "$REPO" && bash "$WSH" add feature-x 2>&1)
echo "$out" | grep -q "another run is probably at work" && echo "$out" | grep -q "worktree.sh landed feature-x" \
    && ok "a fresh claim reads as a run at work, and the action is to wait" || bad "a fresh claim should read as live: $out"
age_claim() { find "$REPO/.worktrees/feature-x" -name .git -prune -o -type f -exec touch -d '2 hours ago' {} +; }
age_claim
out=$(cd "$REPO" && bash "$WSH" add feature-x 2>&1); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q "left nothing" && echo "$out" | grep -q "worktree.sh remove $REPO/.worktrees/feature-x" \
    && ok "an old claim with no work names the remove command" || bad "an old empty claim should name remove (got $rc: $out)"
echo leftover > "$REPO/.worktrees/feature-x/half-done.txt"; age_claim
out=$(cd "$REPO" && bash "$WSH" add feature-x 2>&1)
echo "$out" | grep -q "holds 0 commit(s) and 1 uncommitted file(s)" && echo "$out" | grep -q "Nobody removes it unread" \
    && ok "an old claim with work counts it and keeps it for a person" || bad "an old claim with work should say so: $out"
rm "$REPO/.worktrees/feature-x/half-done.txt"
git -C "$REPO" branch hone/ghost-claim HEAD
out=$(cd "$REPO" && bash "$WSH" add ghost-claim 2>&1); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q "has no worktree, so no run is at work, and it holds 0 commit(s)" \
    && ok "a branch with no worktree reads as a dead claim" || bad "a bare branch claim should say so (got $rc: $out)"
git -C "$REPO" branch -q -D hone/ghost-claim
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
# .hone-review-always decides which docs-only changes still get the full review,
# so an agent that empties it reviews itself less.
out=$(guard_write ".hone-review-always" "$REPO")
denied "$out" && ok "review-always list denied in primary tree" || bad ".hone-review-always should be guard-protected"
out=$(guard_write ".hone-shared" "$REPO")
denied "$out" && ok "shared marker denied in primary tree" || bad ".hone-shared should be guard-protected"

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
echo "== nag: oversized area (advisory, pre-land, only for an area the change touched) =="
(cd "$WT" && mkdir -p src/big && seq 1 40 > src/big/table.js && git add -A && git commit -qm "feat: a big area")
out=$(cd "$WT" && echo '{}' | HONE_AREA_MAX_LINES=30 bash "$NAG" 2>&1)
echo "$out" | grep -q "src/big/ holds 40 lines, over the 30-line cap" && ok "an area over the cap that the change touched is flagged" || bad "should flag src/big/ over HONE_AREA_MAX_LINES"
out=$(cd "$WT" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "holds 40 lines" && bad "an area under the default cap should not be flagged" || ok "an area under the default cap passes"
# A binary file has no lines to read, so it adds nothing to the count.
(cd "$WT" && head -c 4000 /dev/urandom > src/big/blob.bin && git add -A && git commit -qm "chore: a binary asset")
out=$(cd "$WT" && echo '{}' | HONE_AREA_MAX_LINES=30 bash "$NAG" 2>&1)
echo "$out" | grep -q "src/big/ holds 40 lines" && ok "a binary file does not count toward the cap" || bad "a binary file should not change the line count: $out"
# An old large area that this change never touched stays quiet.
(cd "$REPO" && mkdir -p src/old && seq 1 40 > src/old/table.js && git add -A && git commit -qm "chore: an old large area")
WT_AQ="$REPO/.worktrees/area-quiet"
git -C "$REPO" worktree add -q -b hone/area-quiet "$WT_AQ"
(cd "$WT_AQ" && mkdir -p src/calm && seq 1 41 > src/calm/table.js && git add -A && git commit -qm "feat: touch the calm area only")
out=$(cd "$WT_AQ" && echo '{}' | HONE_AREA_MAX_LINES=30 bash "$NAG" 2>&1)
echo "$out" | grep -q "src/calm/ holds 41 lines" && ok "the touched area is flagged" || bad "should flag src/calm/"
echo "$out" | grep -q "src/old/" && bad "an area the change did not touch should stay quiet" || ok "an untouched large area stays quiet"
git -C "$REPO" worktree remove --force "$WT_AQ" && git -C "$REPO" branch -q -D hone/area-quiet

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
echo "== nag: a claim this clone holds with no worktree (shared mode) =="
# A local refs/hone/claim/<change> is this clone's own claim on the remote.
# With no .worktrees/<change> it outlived its run. The nag reads only local
# refs, so the check needs no remote and never touches the network.
git -C "$REPO" update-ref refs/hone/claim/ghost-claim "$(git -C "$REPO" commit-tree "$(git -C "$REPO" hash-object -t tree /dev/null)" -m 'hone claim: ghost-claim by t <t@t.t> on box at now')"
git -C "$REPO" update-ref refs/hone/claim/auth-login "$(git -C "$REPO" commit-tree "$(git -C "$REPO" hash-object -t tree /dev/null)" -m 'hone claim: auth-login by t <t@t.t> on box at now')"
git -C "$REPO" update-ref refs/hone/remote-claim/other-dev "$(git -C "$REPO" commit-tree "$(git -C "$REPO" hash-object -t tree /dev/null)" -m 'hone claim: other-dev by u <u@t.t> on box2 at now')"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "claim on ghost-claim" && ok "stale claim flagged" || bad "should flag a claim with no worktree"
echo "$out" | grep -q "worktree.sh\\\" release ghost-claim\|release ghost-claim" && ok "the finding names the release command" || bad "the stale-claim finding should name worktree.sh release"
echo "$out" | grep -q "claim on auth-login" && bad "a claim with a live worktree should not be flagged" || ok "claim with live worktree not flagged"
echo "$out" | grep -q "other-dev" && bad "another developer's fetched claim is not this clone's leftover" || ok "the team's fetched claims are not flagged"
git -C "$REPO" update-ref -d refs/hone/claim/ghost-claim; git -C "$REPO" update-ref -d refs/hone/claim/auth-login; git -C "$REPO" update-ref -d refs/hone/remote-claim/other-dev

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
echo "== nag: undated spike entry, of any type =="
# The date at the front is the whole signal that a spike is frozen history.
# Without it the entry reads as a live document, and garden would be right to
# treat it as one. Every top-level entry is checked, not only the markdown.
mkdir -p "$REPO/docs/spikes"
printf '# Spike\n' > "$REPO/docs/spikes/sse-backpressure.md"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "sse-backpressure.md carries no date" && ok "undated spike note flagged" || bad "should flag a spike note with no date"
mv "$REPO/docs/spikes/sse-backpressure.md" "$REPO/docs/spikes/2026-08-19-sse-backpressure.md"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "carries no date" && bad "a dated spike note must not be flagged" || ok "dated spike note not flagged"
# A probe is not markdown, and it is checked the same way.
printf 'echo probe\n' > "$REPO/docs/spikes/probe.sh"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "probe.sh carries no date" && ok "undated spike probe flagged" || bad "should flag a non-markdown spike entry with no date"
rm -f "$REPO/docs/spikes/probe.sh"
# A spike of several files uses a dated directory, checked by its own name. The
# nag never looks inside: what a probe names its files is the probe's business.
mkdir -p "$REPO/docs/spikes/2026-08-19-multi/src"
printf 'echo probe\n' > "$REPO/docs/spikes/2026-08-19-multi/src/run.sh"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "carries no date" && bad "a dated spike directory must not be flagged" || ok "dated spike directory not flagged, contents not checked"
mv "$REPO/docs/spikes/2026-08-19-multi" "$REPO/docs/spikes/multi"
out=$(cd "$REPO" && echo '{}' | bash "$NAG" 2>&1)
echo "$out" | grep -q "spikes/multi carries no date" && ok "undated spike directory flagged" || bad "should flag an undated spike directory"
rm -rf "$REPO/docs/spikes"

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
