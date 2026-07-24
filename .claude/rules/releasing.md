---
description: "Maintainer rule for the hone repo: every substantial change bumps the plugin version in a chore: release commit."
---

# Releasing hone

Every substantial change (a feature, or a behavior change to the workflow,
skills, hooks, or critic prompts) must be followed by a version bump. Typo and
comment-level fixes need none.

hone is a distributed Claude Code plugin; consumers only pick up changes through
the marketplace version, so an unbumped change never reaches them.

Bump `version` in **both** `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` (they must always match), in a separate
`chore: release X.Y.Z` commit whose body summarizes the release. Semver: a
feature or behavior change is a minor bump; a fix is a patch.
