---
name: setup
description: "Install hone into a project and verify the install actually works: run the idempotent setup script for the mechanics (test adapter template, gitignore entries, docs skeleton), then author or adapt scripts/run-tests.sh where detection fell short, execute every installed adapter and fix what fails, and complete the protective settings block. Interactive: run once per project with the human present. Invoke with /hone:setup."
disable-model-invocation: true
---

# /hone:setup (install hone and prove the adapters work)

`scripts/setup.sh` handles the deterministic mechanics, but it only guesses at
the test adapter: detection covers Bun, Node, and Python, and it never executes
what it installs. A template that does not fit the project (no `test` script,
a runner that rejects file arguments, a compiler config pinned to a language
standard the toolchain does not support) fails later, in the middle of an
unattended run, where nobody is present to fix it. This command closes that
gap: it runs the script, then verifies each adapter by executing it and fixes
what fails, while the human is still here to approve.

One ordering rule. The deny rules in `.claude/settings.json` exist to stop an
unattended agent from weakening its own checks, so once they are in place,
adapter edits are deliberately hard. If the settings block is not complete yet,
leave it for step 5 so adapter work stays frictionless. If it already is
(a re-run, or the human pasted the README block first), make adapter edits
through a shell write (`cat > scripts/run-tests.sh <<'EOF' ... EOF`): the
file tools are denied outright, but the shell route is escalated by hone's
bash-guard to the human, who is present at setup to approve it. Never treat
that escalation as a reason to skip the fix.

## 1. Mechanics

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"`. It is idempotent: it
installs a template adapter when it can detect the ecosystem, gitignores the
per-developer artifacts, strips `.gitignore` entries earlier hone versions
used, and creates the docs skeleton plus `src/`. Read its output; it names
what it did and what it left alone.

## 2. The test adapter

If the script could not detect the ecosystem, author `scripts/run-tests.sh`
yourself: start from the closest template in
`${CLAUDE_PLUGIN_ROOT}/templates/run-tests/` and meet the contract in that
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
- *Project misconfiguration*: the project side is missing or broken (no
  `test` script in `package.json`, a config pinned to an unsupported language
  standard, integration tests mixed into the unit tier). Fix the project,
  telling the human what you changed and why.
- *Missing toolchain*: the runner or interpreter is not installed. Tell the
  human exactly what to install; do not install toolchains yourself.

## 3. Optional adapters

Where the project already has the tooling, add the one-line optional adapters
and verify each the same way (execute it; exit 0 = clean):

- `scripts/typecheck.sh` when there is a type checker (`tsconfig.json` →
  `tsc --noEmit`; a `mypy`/`pyright` config). It must cover everything the
  repo compiles (`src/`, tests, `scripts/`, tooling), not only production
  code; a checker whose scope stops at `src/` makes the gate's green
  overstate what was checked.
- `scripts/lint.sh` when there is a linter config (`eslint`, `ruff`).

Skip both where the language has no such tool; the gate simply does not run
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

Check `.claude/settings.json` against the install block in hone's README:
the `enabledPlugins` entry, the `Bash(claude -p:*)` allow (without it the
loop's review step can't run unattended), and the deny rules for the adapters
and the settings file itself. Add what is missing last, so the denies land
after the adapters they protect are verified. If the settings file is itself
already deny-protected, show the missing block and let the human paste it.

## 6. Report

Close with what was installed, what was verified green (each adapter and the
exact command that proved it), what was fixed along the way, what was skipped
and why, and what remains optional: `proof.sh`, the committed policy files
(`.hone-durable-paths`, `.hone-irreversible-paths`), and scheduling
`/hone:garden`.
