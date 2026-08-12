# Developing hone

This page is for changing the plugin itself. Using hone in a project is
covered by [`model.md`](model.md) (why it works this way) and
[`reference.md`](reference.md) (the control surface). Where the evaluation
and optimization of the plugin itself is headed is in
[`roadmap.md`](roadmap.md).

## What ships and what doesn't

hone is distributed through its marketplace entry, so a consumer's install is
exactly what `.claude-plugin/plugin.json` describes: `rules/`, `skills/`,
`hooks/`, `agents/`, `scripts/`, and `templates/`. Everything else is
repo-internal and never reaches a consumer: `README.md`, `test/`, `evals/`,
`docs/`, and `.claude/` (this repo's own settings and rules). `README.md` is
the only one of those a stranger reads, because GitHub and the marketplace
listing show it, so it is repo-internal without being private.

The consequence that shapes every change: consumers only pick up a change
through a marketplace version bump. An edit to a distributed file that ships
without a bump reaches nobody. The bump rule lives in
[`.claude/rules/releasing.md`](../.claude/rules/releasing.md), which Claude
Code loads automatically in this repo; if you are working without it, read
that file before releasing.

## The two suites

Which suite a change must pass follows from what it touches.

*Mechanical* — `bash test/run.sh`. Deterministic, no model calls: the hook
unit tests, the end-to-end land path (worktree, gates, merge, rollback), and
two checks over the message templates. Every message hone prints lives in
`hooks/messages.sh`, and the checks lint its prose and hold it to the shape.
Run it after any change to `hooks/` or `scripts/`. The shell sources are also
kept `shellcheck`-clean (`.shellcheckrc` sets the dialect); nothing runs
shellcheck for you, so run it over any script you touch.

*Judgment* — `bash evals/run.sh`. Model-calling: it pins the critic prompts
and the run skill's loop instructions to cases with known-good answers.
[`evals/README.md`](../evals/README.md) is the manual: targets and cases, the
balance between reject and near-miss pass cases, plurality voting, and the
held-out set discipline. Two rules matter most: match the model to what runs
in production (the critics are pinned to `sonnet`; the loop target runs with
`--model opus`), and never read or tune against a `*-holdout` case while
editing prose.

There is no CI; both suites run locally, and the releasing rule is what makes
them a gate.

## Changing judgment prose

The critic prompts (`agents/`), the run skill and its references
(`skills/run/`), and the injected rule (`rules/workflow.md`) are behaviour,
not documentation: treat an edit to them like a code change. Run the relevant
eval target before and after, and when a critic misjudges a real change or
the loop takes a wrong turn, capture it as a new case (see *Extending* in
[`evals/README.md`](../evals/README.md)). The same suite is what licenses
*deleting* prose as models improve: trim, re-run, keep what holds.

## Docs

`docs/` here follows the same economy hone enforces elsewhere: `model.md`
carries the why, `reference.md` the detail, and when the two disagree,
`reference.md` wins and the other page is the bug. A behaviour change is not
done until the page that describes the old behaviour is updated in the same
commit.
