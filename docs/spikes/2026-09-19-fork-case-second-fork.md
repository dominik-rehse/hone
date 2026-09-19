# Spike: why did the `plan-critic` reject a Plan that follows a Decision?

**Date:** 2026-09-19 · **Status:** frozen. Written once, never maintained
against the code.

## Question

The unit case `fork-settled-by-decision` expects an approval. The roadmap
said that it got 15 approvals and 2 rejections over 17 votes. It read that
as a critic that asks what a Decision already answers, in about one Plan of
eight. Is that the mechanism?

## What ran

Each eval call is a headless run from a temporary directory, and its
transcript stays under `~/.claude/projects/-tmp-tmp-*/`. An agent matched
the transcripts of this case by the name of the Decision,
`import-atomicity`. It kept the calls whose system prompt and brief are the
shipped ones, by hash. That gave 23 votes from 2026-09-19, and the 17 of the
roadmap are a subset.

## Result

21 approvals and 2 rejections. Both rejections come from one run of three
votes, and neither concerns the Decision. Both say that the Plan fits
`import-atomicity.md`. Both then name a contradiction in the case itself.
The sketch asks that the operator sees everything that is wrong with the
file. The Plan collected one finding per bad row. So a row with two bad
cells reports only the first. The stub prompt of the ablation rejected for
the same reason, so the lever was in the brief and not in hone's prose. An
earlier rejection, on an earlier brief, named another contradiction in the
brief, and an edit had closed that one.

So the critic was right, and the case held a second fork.

## The fix, and what it showed

Both twin cases now collect one finding per bad cell. Above their context
block they are identical. They differ only in the Decision that the
context holds.

- `fork-settled-by-decision`: 10 approvals of 10. The stub approves 3 of 3.
  The prompt without its two sentences on Decisions approves 3 of 3. So the
  case pins no prompt text. The earlier claim that the prompt without those
  sentences was its baseline rested on the flaw. The case stays as the
  approving twin: a wording that makes the critic reject every fork fails
  it.
- `fork-closed-by-author`: 28 rejections of 30, each for `ambiguity`. On
  the flawed brief it had 15 of 15, so the second fork had helped it. Both
  approving votes see the fork. They apply the prompt's own test and find
  that nothing outside the code depends on the pick, so they call it detail.
  That reading is defensible for this brief. At three votes the case fails
  by chance in about one run of 75.

## What it means

No wording of the critic changes. The two sentences on Decisions move no
case today, so they are a candidate for a trim. A trim of this paragraph
is risky, because three words once moved the lab scenario `plan-fork` from
3 of 3 to 0 of 3.

## Where it landed

`evals/plan-critic/fork-settled-by-decision/`,
`evals/plan-critic/fork-closed-by-author/`, and the case ledger in
`evals/README.md`. [`roadmap.md`](../roadmap.md) carries the corrected item.
