# Spike: the GEPA pilot on the `plan-critic`

**Date:** 2026-09-20 · **Status:** partial, and frozen at that. The session
stopped at the maintainer's word, with the plan's weekly limit at half.
*[Work left](#the-work-left)* hands the rest to the next worker.

Step 6 of the handoff runs a text search over the `plan-critic`. This note
has the adjudication of the labels and the setup. It also has what the run
spent, what the search found so far, and the commands that finish it.

## Phase A: the labels, and it is done

The seed run of claude-opus-5 disagreed with 36 field labels in the train
and validation parts. A field label is the production verdict of
claude-sonnet-5, so part of that gap is label noise. A search against wrong
labels would loosen the critic. So four readers on claude-opus-5 judged the
36 first, nine items each. Each reader saw the brief, the label and its
source, the chain's later calls, and opus's reply. The rubric is
`/var/tmp/hone-optimize/adjudication/RUBRIC.md`, and the result is
`/var/tmp/hone-optimize/adjudication/adjudication.json`.

| judgment | items | what the search does with it |
| --- | --- | --- |
| label-right | 34 | keep the label |
| critic-right | 1 | flip the label |
| unclear | 1 | score it on neither side |

So the labels are sound, and the disagreement is the critic. In 34 of 36
cases opus rejected a Plan that the production run approved. Each rejection
rests on one of three things. It needs a fact that only a file read settles.
It names a pick that flips for free. Or it finds a real but non-blocking
defect and treats it as a gate. All three are petty rejections, and a petty
rejection costs a round trip of a person's attention.

The one flip is a Plan whose brief named a sibling Plan. That sibling
rewrites the same line this Plan pins as preserved. The brief handed the
fact over, the Plan never mentions it, and opus named the conflict by file
and change. The label becomes `REJECT`.

The one `unclear` is a docs-only Plan. Whether it earns its own review gate
turns on a policy file that the offline call could not read. The brief
paraphrased that file in a way that favours rejection. Two readers could
defend either verdict, so the item scores on neither side. The step owner
made that call against one reader's `critic-right`.

**A limit.** Nobody adjudicated the held-out part. Those 51 items keep their
production labels, so a held-out number carries the label noise that Phase A
removed from train and validation. Read a held-out score as a floor.

## What is built

`evals/optimize/` is a Python project, run with `uv` only. Its README says
how to run, stop, and resume a search. `test/gepa_adapter_test.sh` proves
the plumbing with no model call and no network, and `test/run.sh` runs it.

- The candidate is the 14 fine sections of `agents/plan-critic.md`, from
  `sections.py --fine`. Frontmatter and preamble are no components.
- `locks.json` names the five free sections and the nine locked ones, with
  the reason per section. The component selector offers GEPA nothing but the
  free list, and the assembly asserts the locked text again before every
  call.
- `adapter.py` runs each case through `evals/optimize/data/measure.sh`,
  which is `evals/run.sh`'s call shape. It scores 1 for the right verdict
  and 0 for the wrong one, and reports three objectives.
- `search.py` runs a search. `score.py` scores the versions it found.
- The rewriting model is `claude -p` on claude-opus-5, with no tools.

Three guards hold the search honest, and the test proves each one.

- A locked section may not change, and a free section may not empty. The
  floor is a third of the shipped section's words.
- A rewrite that copies a name, a value, or a phrase out of a case goes in
  the bin. The parent's text takes its place. The search saw no such
  proposal in this run.
- An infrastructure error is never a score of 0. An empty reply means a
  usage limit far more often than a model that declined. The adapter waits,
  writes one log line per wait, and the wait has no cap.

One defect cost a restart and is now fixed. The rewriting model returns
prose and drops the blank line that ends a section. The joined file then
glued the next bullet, or the next heading, onto the last sentence, and a
glued `## Output` stopped being a heading. `PromptAssembler.normalize` puts
the tail back, and the test pins it.

## What ran

One search, in `/var/tmp/hone-optimize/runs/2026-09-20-plan-critic-pilot/`.
It ran 23 iterations on 900 metric calls and cost 167.05 dollars of plan
usage, which is 18.6 cents per call. It proposed 17 rewrites and threw none
away. The rewriting model's own calls are on top of that figure, and the
harness does not price them.

The search's own validation set is 44 items: 31 from the private validation
part and hone's 13 visible cases. On it the shipped prompt scores 0.773.

| candidate | parent | aggregate | approve | reject | words |
| --- | --- | --- | --- | --- | --- |
| 0, the shipped prompt | — | 0.773 | 0.722 | 0.808 | 1483 |
| 3 | 2 | 0.841 | **0.882** | 0.815 | 1600 |
| 7 | 0 | 0.818 | 0.714 | **0.913** | 1545 |
| 9 | 0 | 0.841 | 0.850 | 0.833 | 1523 |

The objective front is three versions: the shipped prompt on `words`,
candidate 3 on `approve_right`, and candidate 7 on `reject_right`. Candidate
9 is not on that front, and it is the balanced one: it gains on both labels
and grows the least.

Phase D got through two versions before the stop, on the full adjudicated
validation part of 58 items.

| version | words | approve | reject | accuracy |
| --- | --- | --- | --- | --- |
| the shipped prompt | 1483 | 17/27 | 27/31 | 0.759 |
| approve-first (candidate 3) | 1600 | 18/27 | 27/31 | 0.776 |

One case is not a result. Read that pair as plumbing that works, not as a
finding.

The three versions are in `evals/optimize/candidates/plan-critic/` as
`approve-first.md`, `reject-first.md`, and `balanced.md`. Each one passed
the leak check: no path, identifier, number, or proper noun from a brief.
Diff one against `agents/plan-critic.md` to read the rewrite.

## What the rewrites changed

All four sections the search touched grew. Not one shrank. The rewrites read
as a careful reviewer adding the clause that would have caught the case in
front of it.

- *Missing baseline* (candidate 3) says the sentence has to be in the Plan.
  Background handed over in the brief does not stand in for it, because the
  loop never sees the brief.
- *Contract churn* (candidate 3) adds three clauses. An additive optional
  field is not churn. A narrowing the Plan argues is a decision, not a gap.
  A declared landing order does not help when the later Plan may move a
  value the first already landed.
- *Calibration* (candidate 7) adds a rule against simulating the build
  several steps out to reach a problem. A matching rule forbids treating
  the Plan's own reassurance as a discharge.
- *Prose doing an artifact's job* (candidate 9) says that where the data
  already sits in an artifact the critic stops there. Do not recount its
  rows or re-derive its totals.

## An honest reading

Three things are worth saying plainly.

*The search works, and it does not shrink prose.* `words` was one of three
objectives, and every accepted candidate grew. The reason is structural. The
reflective model reads failures, and a failure suggests a missing rule far
more readily than a redundant one. A search that must shrink needs the cut
proposed on purpose, not hoped for.

*The gain is on approvals, and that is the right half.* The shipped prompt
is right on 72 percent of validation approvals. It is right on 81 percent
of the rejections. Phase A says the same thing from the other side: opus
over-rejects. Both front versions buy their gain there.

*Most of the numbers here are one vote.* `evals/README.md` puts the noise
floor at a flipped plurality over three votes. One vote per case is under
that floor, so a 0.773 against a 0.841 on 44 items is suggestive and no
more. The held-out pass and the suite at three votes are the checks that
would settle it, and neither has run.

A full-budget run would add three things. It would run past 23 iterations,
where the front had moved twice in the last third. It would score every
front version on the held-out part, which is the only check against tuning
to the validation set. And it would run hone's own suite at three votes,
with and without the held-out cases. That suite is the gate a shipped
version must pass anyway.

## The work left

For a worker with no context. Read `evals/optimize/README.md` first, then
`HANDOFF.md` step 6. Install once:

```bash
export UV_PROJECT_ENVIRONMENT=/var/tmp/hone-optimize/venv
export PYTHONDONTWRITEBYTECODE=1
uv sync --project evals/optimize
```

The frugal rules, which the maintainer set on 2026-09-20. One background
process at a time. It waits out the plan's usage limit by itself, so do not
babysit it. Poll every 25 to 30 minutes, and look only at the run's log and
the candidate files. Parallelism stays at 2, because a wide fan-out throws
away everything in flight when the limit hits.

The steps, in order. Each one is one background process.

1. *The smoke run, about 40 calls, about 8 dollars.* Only if you changed the
   adapter. Use a throwaway run directory and `--budget 40`. Read the log
   for one accepted candidate, then stop it with a `gepa.stop` file.
2. *The search, 400 calls, about 75 dollars.* Resume the run that exists:

   ```bash
   uv run --project evals/optimize evals/optimize/search.py \
       --data /var/tmp/hone-optimize/data/plan-critic \
       --adjudication /var/tmp/hone-optimize/adjudication/adjudication.json \
       --run-dir /var/tmp/hone-optimize/runs/2026-09-20-plan-critic-pilot \
       --budget 1300 --jobs 2
   ```

   The budget is cumulative over the run directory, and 900 are spent. So
   1300 buys 400 more.
3. *The scoring, at most three versions, about 60 dollars.* Run one stage at
   a time. `validation` has `shipped` and `approve-first` done already, and
   the cache makes a repeat free. `holdout` runs once, at the end. `suite`
   runs `evals/run.sh` at three votes, with and without the held-out cases.

   ```bash
   uv run --project evals/optimize evals/optimize/score.py \
       --run-dir /var/tmp/hone-optimize/runs/2026-09-20-plan-critic-pilot \
       --data /var/tmp/hone-optimize/data/plan-critic \
       --adjudication /var/tmp/hone-optimize/adjudication/adjudication.json \
       --stage validation --only cand-003,cand-007,cand-009 --jobs 2
   ```
4. *Copy the two or three best* into `evals/optimize/candidates/plan-critic/`
   under a name that says what they buy. `--stage report` prints the table
   and the leak check first. Three are there already, and a better one
   replaces them.

Never read a held-out item or a held-out case, and never show one to the
rewriting model. The private data stays under `/var/tmp/`. Do not edit
`agents/plan-critic.md`: a version ships later, as an ordinary candidate
through `evals/candidate.sh` and the release gate.

### Decisions you must not re-derive

- *The lock list.* `evals/optimize/locks.json` holds it, with the reason per
  section. Free are `slug-collision`, `missing-baseline`,
  `prose-doing-an-artifacts-job`, `contract-churn`, and `calibration`. The
  evidence is the discrimination table of
  [`2026-09-20-critic-data.md`](2026-09-20-critic-data.md) and the section
  ablation of [`2026-09-18-section-ablation-on-opus.md`](2026-09-18-section-ablation-on-opus.md).
  To free one more, move its entry and name the case that aims at it.
- *The objectives.* `approve_right` on approvals only, `reject_right` on
  rejections only, and `words` on every example. GEPA averages an objective
  over the examples that carry it, so leaving a key out is what makes a
  conditional mean come out right. `frontier_type='objective'`.
- *The minibatch is 10.* One vote is noisy, and GEPA's default of 3 is under
  the noise floor.
- *The validation subset is 31 private items plus hone's 13 visible cases.*
  It keeps every generated case aimed at a free section, and every field
  rejection. It samples the field approvals, the locked-category
  rejections, and the harmless edits. The locked-category rejections are
  there so that a rewrite of *Calibration* cannot buy approvals by losing
  rejections elsewhere.
- *The train set is all 143 adjudicated train items* plus the case under
  `evals/optimize/cases/plan-critic/`. Train size costs nothing, because
  only a minibatch runs per iteration.
- *An infrastructure error is never a score.* Read the adapter's header
  before you touch that path.
- *The guard against case content* is two rules, not one. A name is a path,
  an identifier, a number, or a proper noun, and it fails a proposal. An
  ordinary English word is not a leak, because a brief and a review prompt
  share most of their vocabulary. A verbatim run of eight words fails a
  proposal too.
