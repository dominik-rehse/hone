# hone

A Claude Code plugin for test-driven, largely unattended development.

[![version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fdominik-rehse%2Fhone%2Fmain%2F.claude-plugin%2Fplugin.json&query=%24.version&label=version&color=blue)](https://github.com/dominik-rehse/hone)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![platform](https://img.shields.io/badge/platform-Linux%20%2F%20WSL-lightgrey)

You write a short plan for one change. An automated loop then builds it
test-first in an isolated git worktree, runs every check, distills the
documentation, reviews the result, and merges it.

The documentation stays deliberately small. Anything the code, types, or
tests already show gets deleted rather than written down. A maintenance
pass you run between changes keeps cutting what goes stale. Hence the
name: you hone a blade by grinding material away, over repeated passes.

Three documents cover the detail:

- [`docs/model.md`](docs/model.md) covers why it works this way: the
  artifacts, the loop, the checks, the invariants.
- [`docs/reference.md`](docs/reference.md) is the full control surface:
  commands, configuration files, hooks, land gates, exit codes, adapters.
- [`docs/upgrading.md`](docs/upgrading.md) covers taking a repo from an
  earlier hone version to the current one.

[`docs/development.md`](docs/development.md) covers working on hone itself
(the suites, the release process).

## Install

```text
/plugin marketplace add dominik-rehse/hone
/plugin install hone@hone
```

`/plugin install` writes the `enabledPlugins` entry. The permissions are yours
to add, so the complete block in your project's `.claude/settings.json` is:

```json
{
  "enabledPlugins": { "hone@hone": true },
  "permissions": {
    "allow": ["Bash(claude -p:*)"],
    "deny": [
      "Edit(./scripts/run-tests.sh)",
      "Edit(./scripts/typecheck.sh)",
      "Edit(./scripts/lint.sh)",
      "Edit(./scripts/proof.sh)",
      "Edit(./.claude/settings.json)",
      "Edit(./.claude/settings.local.json)",
      "Edit(./.git/hooks/**)",
      "Edit(~/.claude/plugins/**)",
      "Bash(git commit*--no-verify*)"
    ]
  }
}
```

The `allow` entry lets the loop's review step run the native `/code-review`
in a nested headless Claude Code. Without it the run cannot stay
unattended. The `deny` entries stop the file tools from editing the four
adapters, the settings, the git hook wiring, and the plugin's own code.
hone's `bash-guard` hook covers the shell routes to the same files.
`Edit(path)` is the only rule form file permissions match, and it covers
every file-editing tool, Write included. A `Write(path)` rule is inert,
and Claude Code rejects it at startup. Together the rules are a deterrent
against an agent quietly weakening its own checks, not a sandbox. The deny
list above is canonical in the plugin
(`templates/settings/deny-rules.txt`). A session-start warning names any
rule your settings lack. The comparison accepts `Edit(./x)` and `Edit(x)`
alike, in either settings file. Extra project-specific denies on top are
yours to add.

Then, once per project, in a Claude Code session:

```
/hone:setup
```

It runs `scripts/setup.sh` for the mechanics. The script installs a test
adapter `scripts/run-tests.sh` matching your ecosystem, gitignores for the
per-developer files, and the docs skeleton, plus `src/`. The docs skeleton
is `docs/decisions/`, `docs/notes/`, and `docs/open-questions.md`. The
skill then verifies the result: it executes each installed adapter and
adapts it where the template does not fit the project. Examples of a bad
fit: an ecosystem the script cannot detect, a missing `test` script, an
unsupported language standard. It also adds `scripts/typecheck.sh` and
`scripts/lint.sh` where the tooling exists. Running the script directly
with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"` also works, but it
installs without verifying. `scripts/proof.sh` is yours to add. The hooks
use the optional adapters when present.

One layout requirement: production code lives under `src/<area>/` (Python
packages too: `src/<pkg>/`). All of hone's enforcement keys off that layout
and silently does nothing without it.

## Upgrades

```text
/plugin marketplace update hone
/plugin update hone@hone
```

That takes the new plugin version, which is step 1 of
[`docs/upgrading.md`](docs/upgrading.md). The remaining steps re-run setup
and reconcile the repo's own artifacts.

## Use

- `/hone:plan <change>` writes `.plans/<change>.md`, the one hand-written
  artifact: what to build, why, and how you'll know it works. Where prose
  would lose detail (a file format, a fixture, a mockup), attach the actual
  file under `.plans/<change>/`. A critic checks the plan while you are
  still there to fix it. `/hone:plan` then commits the plan so the run can
  see it.
- `/hone:run <change>` executes that plan through the loop and merges it
  green. `/hone:run --all` runs every ready plan, in parallel worktrees
  where the plans are independent, sequentially where they overlap.
- `/hone:herd` is `--all` spread over [herdr](https://github.com/dominik-rehse/herdr)
  tabs. Your tab becomes `MAIN` and orchestrates, and each plan runs in a
  fresh Claude Code session in its own `SUB` tab. A `SUB` tab closes once
  the repository shows its change fully landed, and dependent plans wait for
  that same evidence. Anything a human must do (a probe, a proof) happens in
  the `SUB` tab, never in `MAIN`.
- `/hone:garden` scans the whole repo for staleness between changes (stale
  docs, dead code, redundant tests) and lands the safe deletions. You
  invoke it when you want a maintenance pass. Small, frequent passes beat
  one big sweep.

Exploration sits outside that loop. Throwaway probe code goes in `spikes/`,
which is gitignored and which no hook guards, and you delete it once it has
answered its question. Where the method or the dead ends are worth keeping,
one dated note stays at `docs/spikes/<YYYY-MM-DD>-<slug>.md`, written once and
never updated. That date is what lets a spike note age without becoming a lie,
which is the one exemption from everything above.

You normally type `/hone:plan` and `/hone:run` yourself. Another agent may
invoke them too, so a larger workflow can drive a change end to end.
`/hone:setup`, `/hone:garden`, and `/hone:herd` stay yours alone.

Everything after the plan is automatic. The run stops and reports instead
of proceeding in exactly three cases:

- A check will not go green and the fixes are exhausted.
- The change turns out genuinely ambiguous.
- Landing it needs a real-environment check the run cannot reach: a browser
  journey with no adapter, a canary it cannot watch. A green test suite
  proves nothing about a deployed service.

The land gates are the third case's other half. An irreversible change stops
at the gate, because `git revert` does not undo a dropped column. The run
then reads the diff and records a grant naming what is irreversible and why.
A real-environment change stops until the check has actually run. The run
signs off for a check it ran, and stops for one it cannot. Each record is
stamped with whether the agent or you signed it, and the grant's text lands
in the merge commit.

The run never weakens a check to get through. On a stop, the worktree
stays for inspection, and `worktree.sh grant` / `attest` are the way to
let it proceed.

Check the state of everything with `worktree.sh status`: hooks, adapters,
pending plans, worktrees, sign-offs (see the
[reference](docs/reference.md)).

## Enforcement

Three hooks apply the rules mechanically:

- The *guard* allows no production code without a failing test. It also
  keeps the primary tree a merge target, edited only by landing merges.
- The *gate* requires tests, type-check, and lint to be green before a
  turn may end.
- The *nag* reports hygiene findings visibly, and never blocks.

Two critic agents check the plan and the consolidated result. Their
prompts tell them to find fault rather than approve. Code review reuses
Claude Code's built-in `/code-review`. The details, including every
configuration file and exit code, are in the
[reference](docs/reference.md). The reasoning behind them is in the
[model](docs/model.md).
