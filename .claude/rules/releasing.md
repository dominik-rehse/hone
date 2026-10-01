---
description: "Maintainer rule for the hone repo: every substantial change bumps the plugin version in a chore: release commit."
---

# Releasing hone

Bump the plugin version after every substantial change. That covers a feature,
and a behavior change to the workflow, the skills, the hooks, or the critic
prompts.

A wording change to a skill, a critic prompt, or `rules/workflow.md` is
substantial, and it bumps the version on its own. That prose is what the model
executes, so a reword changes behavior even when no code moves. Treat it like a
code change, not like documentation. The same holds for the shipped docs a
consumer reads.

A docs change bumps too, whenever it alters what a user would do. `docs/` does
not ship through the marketplace, but the bump is what tells a consumer repo to
re-read it.

Two things need no bump. The first is a typo or comment-level fix inside code.
The second is a change to the harness this repo never ships and no user reads:
`test/`, `evals/`, and `.claude/`.

hone is a distributed Claude Code plugin. Consumers only pick up changes through
the marketplace version, so an unbumped change never reaches them.

Bump `version` in **both** `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json`. The two must always match. Make the bump a
separate `chore: release X.Y.Z` commit. Its body summarizes the release. On
semver, a feature or behavior change is a minor bump, and a fix is a patch.
When a change qualifies, do the bump. Do not ask whether it counts.

Some changes alter what hone leaves in a consumer repository: an adapter,
a policy file, the settings block, a docs shape. Such a change ships with
its upgrade path. Make the path mechanical in `scripts/setup.sh` or a
`/hone:garden` pass where you can. Where a person must act, add the step
to `docs/upgrading.md` under the version that made it so. A release without
that path is not complete.

Before the release commit, the changed layer must pass its suite:

- every release: `bash test/run.sh` green. This suite is the regression
  gate. A fix for a shape from real use adds a test there that replays the
  shape, for example the command that a guard judged wrong.
- a change to the wording of the judgment prose: `bash evals/run.sh
  <target> --votes 3 --model opus` green, for the one target that the change
  touches. The judgment prose is the critic prompts (`agents/*.md`),
  `skills/run/SKILL.md` and its references, `skills/garden/SKILL.md`, and
  `rules/workflow.md`. Run no held-out pass and no second model.
- a new eval case, before you keep it: `bash evals/run.sh <target> --ablate`.
  A case that the stub also passes pins nothing, so it does not go in.
- a change to a guard (`hooks/bash-guard.sh`, `hooks/guard.sh`,
  `hooks/dirty-guard.sh`): a code review of the diff at `high` that hunts
  for commands the change lets past. 0.62.0 passed the lab 21 of 21 and
  every suite, and a review then found about twenty such routes.

A release does not run the lab (`evals/lab/run.sh`). The lab costs about
40 dollars and an hour a pass. From 2026-09-27 to 2026-09-29 it passed six
releases and found one small defect, and it never ran the code that real
use then broke. Run it only on the maintainer's word, for example before a
large rework of the run loop. Read a failed scenario in its sandbox before
you trust it, because some fails were bugs in a check.

## The model slots

The critics' frontmatter and the review command in `skills/run/SKILL.md`
each name the `opus` alias, on the maintainer's decision of 2026-09-24.
`test/prose_test.sh` fails on anything else there. The slots therefore
follow the newest Opus with no hone release. A consumer gets a new Opus
when Claude Code re-points the alias, whether or not the suites ran on it.

## When a new model is released

A new model can read the same prose differently, in both directions. For a
new Opus, do this as soon as `opus` resolves to it, because consumers
already run on it. `bash evals/run.sh` prints the model ID it resolved.

Run all four eval targets on the new ID at `--votes 3`. Run the lab once,
and the cheating benchmark in `evals/probes/impossiblebench/` once. Date the
result in a note under `docs/spikes/`. A tally below 3/3 on any case means
the prose does not hold on the new model. Fix the prose in a release of its
own. The lab's transparency scenarios and the cheating benchmark are hone's
evidence for its main claim. So run them a few times a year as well, when
the maintainer asks.

Measure nothing more than this without the maintainer's word. On opus the
extra measures found nothing that real use did not find sooner
([the audit](../../docs/spikes/2026-09-27-eval-lab-value-audit.md)).

## The docs sweep

hone states each behavior in more than one place, on purpose. The reference
is for the operator, the model doc for the why, the skills for the model,
and the README for the first read. A behavior change therefore goes stale somewhere
else unless you look. `test/prose_test.sh` catches the mechanical half: a
subcommand, marker, tunable, or hook with no reference entry. The other half
is a sentence that now describes the old behavior, and no script reads
meaning. So before the release commit, do this by hand:

1. Write down the nouns and verbs the change touched. Examples: `attest`,
   `sign-off`, `push`, `primary tree`, `claim`, `exit 5`.
2. Grep the whole repo for each, not only the files you edited:
   `grep -rn -i '<term>' README.md docs rules skills agents templates hooks
   scripts evals/README.md`.
3. Read every hit as a claim about behavior, and ask whether it is still
   true. Fix or delete what is not. A code comment counts, and so does a
   message template.

These files restate behavior most often, and so go stale most often:

- `README.md`, `docs/model.md`, `docs/reference.md`, `docs/upgrading.md`
- `rules/workflow.md`, every `skills/*/SKILL.md`, `skills/run/references/*.md`
- `templates/*/README.md`, `templates/settings/deny-rules.txt`
- the header comment of `scripts/worktree.sh`, the header comments of `hooks/*.sh`
- the case ledger in `evals/README.md`

An eval case's `expected` answer is a claim too: a rule change can flip it.

One more check that has bitten: a new message template's `Do:` line must
not hand the agent a route around a gate or a policy file. Read each new
template as the agent would.

## After the push

The push is what makes a release reachable, and the maintainer's own repos
take it in two more steps. Each has hone installed at project scope:
`~/repos/agent`, `~/repos/capital-provider-db`, `~/repos/fileduct`, and
`~/repos/mailduct`.

```
git push origin main
claude plugin marketplace update hone
cd ~/repos/<repo> && claude plugin update hone@hone --scope project --yes
```

The marketplace clone under `~/.claude/plugins/marketplaces/hone` is what the
update reads, and only the second command refreshes it. Run the third once
per repo, from inside it. Sessions in those repos must restart to load the
new hooks. Confirm the version per repo in
`~/.claude/plugins/installed_plugins.json`. Do these steps as part of the
release, not as a suggestion afterwards.
