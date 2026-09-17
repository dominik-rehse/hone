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

Before the release commit, the changed layer must pass its suite:

- a change to a critic prompt (`agents/*.md`), to `skills/run/SKILL.md` or its
  references, to `skills/garden/SKILL.md`, or to `rules/workflow.md`:
  `bash evals/run.sh <target> --votes 3` green, then `--holdout` green as the
  final check. See `evals/README.md` on held-out cases. The `loop` and `garden`
  targets run with `--model opus`.
- a new eval case, before you keep it: `bash evals/run.sh <target> --ablate`,
  and the second baseline in `evals/README.md` when the stub agrees with the
  expected answer. A case that discriminates against neither baseline pins
  nothing, so it does not go in.
- a change to hooks or scripts: `bash test/run.sh` green.

## Moving a model pin

The critics' frontmatter and the review command in `skills/run/SKILL.md`
each carry a full model ID. `test/prose_test.sh` fails on an alias there. A
move to another ID is a behavior change, so it is a minor bump. Before the
release commit, run all four eval targets on the new IDs at `--votes 3`,
then with `--holdout`. Then re-measure the noise floor and date it in
`evals/README.md`. A new tally below 3/3 on any case means the new model
does not hold the slot yet.

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
