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
separate `chore: release X.Y.Z` commit whose body summarizes the release. On
semver, a feature or behavior change is a minor bump, and a fix is a patch.

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
