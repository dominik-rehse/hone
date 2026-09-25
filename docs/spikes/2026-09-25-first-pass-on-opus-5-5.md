# Spike: does hone's prose hold on claude-opus-5-5?

**Date:** 2026-09-25 · **Status:** frozen. Written once, never maintained
against the code.

## Question

On 2026-09-24 the critics and the nested `/code-review` moved from
claude-opus-5 to the `opus` alias, which resolved to claude-opus-5-5. The same
commits cut the assume-the-worst openings of both critics. Does every suite
still hold, and which floors move?

## What I did

On commit 90f280b, with Claude Code 2.1.282:

- `bash evals/run.sh all --votes 3 --model opus`, three times, for the
  unit suites and the noise floor. `--holdout` once more on top.
- `bash evals/run.sh garden --votes 3 --model sonnet`, with and without
  `--holdout`, for the floor of garden.
- `bash evals/lab/run.sh --model claude-opus-5-5`, every scenario once, into
  `/var/tmp/hone-lab/20260925-102747/`. Then `bypass-hook` once more, into
  `/var/tmp/hone-lab/20260925-105910/`.

The unit passes cost 15.60 dollars and the lab 15.95 dollars, at API prices.

## Finding

- Every unit case held at 3/3: 33 visible cases and 4 held-out cases on
  claude-opus-5-5, and garden's 5 on claude-sonnet-5.
- The noise floor: 297 votes over three passes, no plurality flipped, and no
  vote dissented. A pass cost 3.47 to 3.85 dollars.
- The lab: 20 of 21 scenarios passed, and none was indeterminate.
  `bypass-hook` failed on its check that the review runs once. The loop
  started the review without the `cd` into the worktree. It then read the
  empty `.part` file as the end of the task and started a second review,
  while the first still ran. Both envelopes were valid. The rerun passed, so
  the defect showed in 1 of 2 runs.
- One measure was off its goal: `python-structure` had `cc_pile piled`. The
  write-off went inline into the ledger's apply function. That is the open
  defect from the [baseline](2026-09-19-python-structure-baseline.md), not a
  new one.
- The review on claude-opus-5-5 kept its shape: one call, `num_turns` 0,
  and a valid envelope.

## Where it landed

- `evals/floors` names claude-opus-5-5 for the critics, the loop, and the
  lab. It is the cheapest model that held each suite. Garden stays on
  claude-sonnet-5.
- The noise-floor row is in `evals/README.md`.
- The second review is a defect in `docs/roadmap.md`.
