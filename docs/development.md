# Developing hone

This page is for changing the plugin itself. [`model.md`](model.md) (why it
works this way) and [`reference.md`](reference.md) (the control surface)
cover using hone in a project. [`roadmap.md`](roadmap.md) covers the plan
for evaluating and optimizing the plugin itself.

## What ships and what doesn't

hone reaches consumers through its marketplace entry, so an install is
exactly what `.claude-plugin/plugin.json` describes: `rules/`, `skills/`,
`hooks/`, `agents/`, `scripts/`, and `templates/`. Everything else is
repo-internal and never reaches a consumer: `README.md`, `test/`, `evals/`,
`docs/`, and `.claude/` (this repo's own settings and rules). `README.md`
is the only one of those a stranger reads, because GitHub and the
marketplace listing show it, so it is repo-internal without being private.

The consequence that shapes every change: consumers only pick up a change
through a marketplace version bump. An edit to a distributed file that
ships without a bump reaches nobody. The bump rule lives in
[`.claude/rules/releasing.md`](../.claude/rules/releasing.md), and Claude
Code loads it automatically in this repo. If your session did not load it,
read that file before releasing.

## The two suites

Which suite a change must pass follows from what it touches.

*Mechanical*: `bash test/run.sh`. It is deterministic and makes no model
calls. It covers the hook unit tests, the end-to-end land path (worktree,
gates, merge, rollback), and two checks over the message templates. Every
message hone prints lives in `hooks/messages.sh`, and the checks lint its
prose and hold it to the shape. Run this suite after any change to
`hooks/` or `scripts/`. The shell sources also stay `shellcheck`-clean
(`.shellcheckrc` sets the dialect). Nothing runs shellcheck for you, so
run it over any script you touch.

*Judgment*: `bash evals/run.sh`. This suite calls models. It pins the
critic prompts and the run skill's loop instructions to cases with
known-good answers. [`evals/README.md`](../evals/README.md) is the manual:
targets and cases, the balance between reject and near-miss pass cases,
plurality voting, and the held-out set discipline. Two rules matter most.
Match the model to what runs in production: the critic frontmatter pins
`sonnet`, and the loop target runs with `--model opus`. And never read or
tune against a `*-holdout` case while editing prose.

There is no CI. Both suites run locally, and the releasing rule is what
makes them a gate.

## Changing judgment prose

The critic prompts (`agents/`), the run skill and its references
(`skills/run/`), and the injected rule (`rules/workflow.md`) are behavior,
not documentation. Treat an edit to them like a code change. Run the
relevant eval target before and after the edit. When a critic misjudges a
real change or the loop takes a wrong turn, capture it as a new case.
*Extending* in [`evals/README.md`](../evals/README.md) shows how. The same
suite is what makes *deleting* prose safe as models improve: trim, re-run,
and keep what holds.

## Change briefs

A brief for work on hone itself lives at `.plans/<slug>.md`, in the shape the
`plan` skill defines. This repo is not self-hosted, so no loop executes the
brief and no consolidate deletes it. A human does both. The brief is still
tracked, still one file, and still gone from the tree once the work lands. The
commit that finishes the work deletes it, and git history keeps it. Do not
invent a second place or a second shape for the same artifact.

The `plan-critic` has usually not seen such a brief. Say so in the brief when
it has not.

## Docs

`docs/` here follows the same honing hone enforces elsewhere: `model.md`
carries the why, and `reference.md` carries the detail. When the two
disagree, `reference.md` wins, and the other page is the bug. A behavior
change is not done until the same commit updates the page that describes
the old behavior.
