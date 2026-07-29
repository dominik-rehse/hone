# hone

A Claude Code plugin for test-driven, largely unattended development.

[![version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fdominik-rehse%2Fhone%2Fmain%2F.claude-plugin%2Fplugin.json&query=%24.version&label=version&color=blue)](https://github.com/dominik-rehse/hone)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![platform](https://img.shields.io/badge/platform-Linux%20%2F%20WSL-lightgrey)

You write a short plan for one change; an automated loop builds it test-first
in an isolated git worktree, runs every check, distills the documentation,
reviews the result, and merges it.

Documentation is kept deliberately small: anything the code, types, or tests
already show gets deleted rather than written down, and a maintenance pass you
run between changes keeps cutting what goes stale. Hence the name: you hone a
blade by grinding material away, over repeated passes, and never by adding to
it.

Three documents cover the detail:

- [`docs/model.md`](docs/model.md) covers why it works this way: the
  artifacts, the loop, the checks, the invariants.
- [`docs/reference.md`](docs/reference.md) is the full control surface:
  commands, configuration files, hooks, land gates, exit codes, adapters.
- [`docs/upgrading.md`](docs/upgrading.md) covers taking a repo from an
  earlier hone version to the current one.

Working on hone itself (the suites, the release process) is covered in
[`docs/development.md`](docs/development.md).

## Install

Add the plugin and enable it in your project's `.claude/settings.json`:

```json
{
  "enabledPlugins": { "hone@hone": true },
  "permissions": {
    "allow": ["Bash(claude -p:*)"],
    "deny": [
      "Edit(./scripts/run-tests.sh)",
      "Edit(./scripts/typecheck.sh)",
      "Edit(./scripts/lint.sh)",
      "Edit(./.claude/settings.json)"
    ]
  }
}
```

The `allow` entry lets the loop's review step run the native `/code-review`
in a nested headless Claude Code; without it the run can't stay unattended.
The `deny` entries stop the file tools from editing the test adapter or the
settings; hone's `bash-guard` hook covers the shell routes to the same files.
`Edit(path)` is the only rule form file permissions match, and it covers every
file-editing tool, Write included — a `Write(path)` rule is inert and Claude
Code rejects it at startup.
Together they are a deterrent against an agent quietly weakening its own
checks, not a sandbox. A session-start warning fires if the deny rules are
missing.

Then, once per project, in a Claude Code session:

```
/hone:setup
```

It runs `scripts/setup.sh` for the mechanics (a test adapter
`scripts/run-tests.sh` matching your ecosystem, gitignores for the
per-developer files, the docs skeleton of `docs/decisions/`, `docs/notes/`,
and `docs/open-questions.md`, plus `src/`) and then verifies the result: it
executes each installed adapter, adapts it where the template doesn't fit the
project (an ecosystem the script can't detect, a missing `test` script, an
unsupported language standard), and adds `scripts/typecheck.sh` /
`scripts/lint.sh` where the tooling exists. Running the script directly with
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"` also works, but installs
without verifying. `scripts/proof.sh` is yours to add; the hooks use the
optional adapters when present.

One layout requirement: production code lives under `src/<area>/` (Python
packages too: `src/<pkg>/`). All of hone's enforcement keys off that layout
and silently does nothing without it.

## Use

- `/hone:plan <change>` writes `.plans/<change>.md`, the one hand-written
  artifact: what to build, why, and how you'll know it works. Where prose
  would lose detail (a file format, a fixture, a mockup), attach the actual
  file under `.plans/<change>/`. A critic checks the plan while you are still
  there to fix it, and it is committed so the run can see it.
- `/hone:run <change>` executes that plan through the loop and merges it
  green. `/hone:run --all` runs every ready plan, in parallel worktrees where
  the plans are independent, sequentially where they overlap.
- `/hone:garden` scans the whole repo for staleness between changes (stale
  docs, dead code, redundant tests) and lands the safe deletions. You invoke
  it when you want a maintenance pass; small and often beats one big sweep.

Everything after the plan is automatic. The run stops and reports instead of
proceeding in exactly three cases: a check won't go green and the fixes are
exhausted; the change turns out genuinely ambiguous; or landing it needs
something only you can give, either a grant for an irreversible change (a
dropped column is not undone by `git revert`) or a sign-off that a
real-environment check ran (a green test suite proves nothing about a browser
journey or a deployed service). It never weakens a check to get through; on a
stop, the worktree stays for inspection and `worktree.sh grant` / `attest` are
the way to let it proceed.

Check the state of everything with `worktree.sh status`: hooks, adapters,
pending plans, worktrees, sign-offs (see the
[reference](docs/reference.md)).

## Enforcement

Three hooks apply the rules mechanically: the *guard* (no production code
without a failing test; the primary tree is a merge target, edited only by
landing merges), the *gate* (tests, type-check, and lint must be green before
a turn may end), and the advisory *nag* (hygiene findings, visibly reported,
never blocking). Two critic agents, each prompted to find fault rather than
approve, check the plan and the consolidated result; code review reuses
Claude Code's built-in `/code-review`. The details, including every
configuration file and exit code, are in the
[reference](docs/reference.md); the reasoning behind them is in the
[model](docs/model.md).
