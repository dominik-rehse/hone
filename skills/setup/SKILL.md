---
name: setup
description: "Install hone into a project and verify the install actually works: run the idempotent setup script for the mechanics (test adapter template, gitignore entries, docs skeleton), then author or adapt scripts/run-tests.sh where detection fell short, execute every installed adapter and fix what fails, and complete the protective settings block. Interactive: run once per project with the human present. Invoke with /hone:setup."
disable-model-invocation: true
---

# /hone:setup (install hone and prove the adapters work)

`scripts/setup.sh` handles the deterministic mechanics, but it only guesses at
the test adapter: detection covers Bun, Node, and Python, and it never executes
what it installs. A template that does not fit the project fails later, in the
middle of an unattended run, where nobody is present to fix it. The project may
have no `test` script, a runner that rejects file arguments, or a compiler
config pinned to an unsupported language standard. This command closes that
gap. It runs the script, then verifies each adapter by executing it and fixes
what fails, while the human is still here to approve.

One ordering rule. The deny rules in `.claude/settings.json` exist to stop an
unattended agent from weakening its own checks. Once they are in place,
adapter edits are deliberately hard. If the settings block is not complete yet,
leave it for step 5 so adapter work stays frictionless. If it already is
(a re-run, or the human pasted the README block first), make adapter edits
through a shell write. Use `cat > scripts/run-tests.sh <<'EOF' ... EOF`. The
file tools are denied outright, but hone's bash-guard escalates the shell
route to the human, who is present at setup to approve it. Never treat
that escalation as a reason to skip the fix.

## 1. Mechanics

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"`. It is idempotent. It
installs a template adapter when it can detect the ecosystem, and gitignores
the per-developer artifacts. It strips `.gitignore` entries earlier hone
versions used, and creates the docs skeleton plus `src/`. Read its output. It
names what it did and what it left alone.

## 2. The test adapter

If the script could not detect the ecosystem, author `scripts/run-tests.sh`
yourself. Start from the closest template in
`${CLAUDE_PLUGIN_ROOT}/templates/run-tests/`. Meet the contract in that
directory's `README.md` (unit tier by default, `--all` every tier, `--unit`
explicit, `<files...>` exact selection, exit 0 = pass).

Then verify by executing, whether the adapter is fresh, pre-existing, or one
you just wrote:

- `bash scripts/run-tests.sh` exits 0 on a passing (or empty) suite.
- `bash scripts/run-tests.sh <one test file>` runs exactly that file, if the
  project has any test to try it on.
- `bash scripts/run-tests.sh --all` accepts the flag without erroring.

React to what fails instead of reporting it. Distinguish three causes:

- *Adapter bug*: the template's assumption does not hold (wrong runner, an
  argument-passing quirk, tiers not separated). Fix the adapter script.
- *Project misconfiguration*: the project side is missing or broken. It has no
  `test` script in `package.json`, or a config pinned to an unsupported
  language standard, or integration tests mixed into the unit tier. Fix the
  project, telling the human what you changed and why.
- *Missing toolchain*: the runner or interpreter is not installed. Tell the
  human exactly what to install. Do not install toolchains yourself.

## 3. Optional adapters

Where the project already has the tooling, add the one-line optional adapters
and verify each the same way (execute it, exit 0 = clean):

- `scripts/typecheck.sh` when there is a type checker (`tsconfig.json` →
  `tsc --noEmit`, a `mypy`/`pyright` config). It must cover everything the
  repo compiles (`src/`, tests, `scripts/`, tooling), not only production
  code. A checker whose scope stops at `src/` makes the gate's green
  overstate what was checked.
- `scripts/lint.sh` when there is a linter config (`eslint`, `ruff`).
- `scripts/setup-tree.sh` when the ecosystem has an install step (`bun.lock`
  → `bun install`, `package-lock.json` → `npm ci`, `uv.lock` → `uv sync`).
  It makes the current tree runnable. `worktree.sh add` runs it in every
  fresh worktree, and land runs it in the primary tree when the merged diff
  touched a lockfile. Verify it by executing it once here.

Skip these where the language has no such tool. The gate simply does not run
them. `scripts/proof.sh` stays with the human: mention the templates under
`${CLAUDE_PLUGIN_ROOT}/templates/proof/` for changes that will need
real-environment proof, but do not author it unprompted.

## 4. Layout

hone's enforcement keys off code living under `src/<area>/` and silently does
nothing elsewhere. If the project keeps production code somewhere else
(`lib/`, `app/`, a flat root), say so explicitly and ask whether to move it.
Never relocate code on your own: that restructuring is its own change, through
its own Plan.

## 5. Settings

Check `.claude/settings.json` for the `enabledPlugins` entry and the
`Bash(claude -p:*)` allow (without it the loop's review step can't run
unattended). For the deny rules, `setup.sh` already printed exactly which
canonical rules are missing. It compares both settings files against
`${CLAUDE_PLUGIN_ROOT}/templates/settings/deny-rules.txt`, accepting the
`Edit(./x)` and `Edit(x)` spellings alike. Do not re-derive the list
yourself. Add what is missing last, so the denies land after the adapters
they protect are verified. Rules a project carries beyond the canonical set
are its own policy: leave them alone. If the settings file is itself already
deny-protected, show the missing entries and let the human paste them.

This step is also the upgrade path. When a new hone version grows the
canonical list, re-running `/hone:setup` (or `setup.sh` alone) reduces the
reconciliation to the same single paste.

## 6. Report

Close with what was installed and what was verified green (each adapter and
the exact command that proved it). Cover what was fixed along the way, and
what was skipped and why. What remains optional: `proof.sh`, the committed
policy files (`.hone-durable-paths`, `.hone-irreversible-paths`), and the
maintenance pass `/hone:garden`, once there is enough written down to go
stale.
