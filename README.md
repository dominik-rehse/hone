# hone

A Claude Code plugin for test-driven, largely unattended development.

[![version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fdominik-rehse%2Fhone%2Fmain%2F.claude-plugin%2Fplugin.json&query=%24.version&label=version&color=blue)](https://github.com/dominik-rehse/hone)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![platform](https://img.shields.io/badge/platform-Linux%20%2F%20WSL-lightgrey)

You write a short plan for one change. An automated loop then builds the
change test-first in an isolated git worktree, runs every check, distills
the documentation, reviews the result, and merges it.

hone has two main characteristics: the honing and the enforcement.

## Honing

The documentation stays deliberately small. When the code, the types, or
the tests already carry a fact, hone deletes the prose that repeats it.
hone expects every change to delete something. Between changes, a
maintenance pass (`/hone:garden`) cuts what has gone stale since. This is
the source of the name: to hone a blade, you grind material away, in
repeated passes.

## Enforcement

Three hooks apply the rules mechanically:

- The *guard* allows no production code without a failing test. It also
  keeps the primary tree a merge target, edited only by landing merges.
- The *gate* requires tests, type-check, and lint to be green before a
  turn may end.
- The *nag* reports hygiene findings visibly, and never blocks.

Two critic agents check the plan and the consolidated result. Their
prompts tell them to find fault rather than approve. Code review reuses
Claude Code's built-in `/code-review`. Two land gates stop an
irreversible or real-environment change until a person or the run signs
it off in writing (see *Use* below).

## Documentation

- [`docs/model.md`](docs/model.md) explains why hone works this way: the
  artifacts, the loop, the checks, the invariants.
- [`docs/reference.md`](docs/reference.md) is the full control surface:
  commands, configuration files, hooks, land gates, exit codes, adapters.
- [`docs/upgrading.md`](docs/upgrading.md) explains how to take a repo
  from an earlier hone version to the current one.
- [`docs/development.md`](docs/development.md) explains how to work on
  hone itself: the suites and the release process.

## Install

```text
/plugin marketplace add dominik-rehse/hone
/plugin install hone@hone
```

`/plugin install` writes the `enabledPlugins` entry. You add the
permissions yourself, so the complete block in your project's
`.claude/settings.json` is:

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

The `allow` entry lets the loop's review step run the native
`/code-review` in a nested headless Claude Code. Without it the run
cannot stay unattended.

The `deny` entries stop the file tools from editing the four adapters,
the settings, the git hook wiring, and the plugin's own code. hone's
`bash-guard` hook covers the shell routes to the same files. File
permissions match only the `Edit(path)` rule form, and that form covers
every file-editing tool, Write included. A `Write(path)` rule does
nothing, and Claude Code rejects it at startup. The rules deter an agent
from quietly weakening its own checks. They are not a sandbox.

The deny list above is canonical in the plugin
(`templates/settings/deny-rules.txt`). A session-start warning names any
rule your settings lack. The comparison accepts `Edit(./x)` and `Edit(x)`
alike, in either settings file. You can add extra project-specific denies
on top.

Then, once per project, in a Claude Code session:

```
/hone:setup
```

It runs `scripts/setup.sh` for the mechanics. The script installs a test
adapter `scripts/run-tests.sh` for your ecosystem, gitignores for the
per-developer files, the docs skeleton, and `src/`. The docs skeleton is
`docs/decisions/`, `docs/notes/`, and `docs/open-questions.md`. The skill
then verifies the result: it executes each installed adapter and adapts
it where the template does not fit the project. Examples of a bad fit: an
ecosystem the script cannot detect, a missing `test` script, an
unsupported language standard. The skill also adds `scripts/typecheck.sh`
and `scripts/lint.sh` where the tooling exists. You can run the script
directly with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"`, but then
nothing verifies the install. You add `scripts/proof.sh` yourself. The
hooks use the optional adapters when present.

One layout requirement: production code lives under `src/<area>/` (Python
packages too: `src/<pkg>/`). All of hone's enforcement depends on that
layout and does nothing without it.

## Upgrades

```text
/plugin marketplace update hone
/plugin update hone@hone
```

That takes the new plugin version, which is step 1 of
[`docs/upgrading.md`](docs/upgrading.md). The remaining steps re-run
setup and reconcile the repo's own artifacts.

## Use

- `/hone:plan <change>` writes `.plans/<change>.md`, the one hand-written
  artifact: what to build, why, and how you will know it works. Where
  prose would lose detail (a file format, a fixture, a mockup), attach
  the actual file under `.plans/<change>/`. A critic checks the plan
  while you are still there to fix it. `/hone:plan` then commits the plan
  so the run can see it.
- `/hone:run <change>` executes that plan through the loop and merges it
  once every check is green. `/hone:run --all` runs every ready plan: in
  parallel worktrees where the plans are independent, sequentially where
  they overlap. Inside [herdr](https://github.com/dominik-rehse/herdr),
  `--all` spreads those plans over herdr tabs by itself. Your tab becomes
  `MAIN` and orchestrates. Each plan runs in a fresh Claude Code session
  in its own `SUB` tab. A `SUB` tab closes once the repository shows its
  change fully landed, and dependent plans wait for that same evidence.
  Anything a human must do (a probe, a proof) happens in the `SUB` tab,
  never in `MAIN`.
- `/hone:garden` scans the whole repo for staleness between changes
  (stale docs, dead code, redundant tests) and lands the safe deletions.
  You invoke it when you want a maintenance pass. Small, frequent passes
  work better than one large pass.

Exploration sits outside that loop. A probe writes whatever it needs
under `docs/spikes/`, where no hook guards it: no test first, no
worktree, any file type. Most probes answer their question and leave
nothing behind. Keep one when its method or its dead ends are worth
having. The whole spike then stays under one dated stem,
`docs/spikes/<YYYY-MM-DD>-<slug>`: the probe code, what it captured, and
a note. The date marks the spike as a record of its time, so it can go
stale without misleading a reader. It is the one exemption from
everything above.

You normally type `/hone:plan` and `/hone:run` yourself. Another agent
may invoke them too, so a larger workflow can drive a change end to end.
Only you invoke `/hone:setup` and `/hone:garden`.

Everything after the plan is automatic. The run stops and reports instead
of proceeding in exactly three cases:

- A check stays red after the run has tried every fix.
- The change turns out to be genuinely ambiguous.
- Landing the change needs a real-environment check the run cannot reach:
  a browser journey with no adapter, a canary it cannot watch. A green
  test suite proves nothing about a deployed service.

The land gates back the third case. An irreversible change stops at the
authority gate, because `git revert` does not undo a dropped column. The
run then reads the diff and records a grant that names what is
irreversible and why. A real-environment change stops at the proof gate
until the check has actually run. The run signs off for a check it ran,
and stops for one it cannot reach. `worktree.sh` stamps each record
with its signer, the agent or you, and the grant's text lands in the
merge commit.

The run never weakens a check to get through. On a stop, the worktree
stays for inspection. `worktree.sh grant` and `worktree.sh attest` are
the way to let the run proceed.

Check the state of everything with `worktree.sh status`: hooks, adapters,
pending plans, worktrees, sign-offs (see the
[reference](docs/reference.md)).
