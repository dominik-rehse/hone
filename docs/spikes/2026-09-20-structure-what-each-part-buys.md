# Spike: what does each model-calling part of hone buy?

**Date:** 2026-09-20 · **Status:** partial, and frozen at that.
The campaign stopped on the plan's weekly limit.
[*Work that is left*](#work-that-is-left) says what to run next.

## Question

Step 5 of `HANDOFF.md`, for the parts that call a model. Another worker
measures the hooks. On claude-opus-5 hone makes one measured difference so
far. On the ten seeds of the transparent room set a bare session leaves a
false sentence on 8 seeds of 10. hone held the outcome in 30 runs of 30.

So which part does the catching? And what does each part cost?

## What a part costs

No new run. The splitter is the run skill's own status line. The loop
prints one line per step, and the last step marked `✓` is the step that
just finished. A step runs from the previous `✓` to its own. The
`consolidate-critic` is the sub-agent inside the consolidate window, and
its messages carry `parent_tool_use_id`. The nested `/code-review` runs in
another process, so its price is `nested_cost_usd`.

All 49 complete full-arm runs of the room set gave all six boundaries, so
the cut is not a guess. The price per message is less exact. Cache reads
are exact, and they are the largest term. Output tokens are estimated from
the characters of each message and then scaled to the run's total. Output
is about a third of a run, so a step's share carries a few points of error.

Room set, full arm, claude-opus-5, n=49 runs, mean 2.04 dollars and 7.7
minutes. `words` is what the variant builder removes for that part.

| part | $ | share | min | turns | words |
| --- | --- | --- | --- | --- | --- |
| setup and worktree | 0.275 | 13% | 0.31 | 4.2 | 0 |
| build | 0.184 | 9% | 0.40 | 6.1 | 156 |
| verify | 0.073 | 4% | 0.36 | 2.3 | 436 |
| consolidate, no critic | 0.451 | 22% | 2.41 | 9.5 | 516 |
| `consolidate-critic` | 0.077 | 4% | 0.55 | 4.6 | 1120 |
| review | 0.797 | 39% | 2.93 | 7.9 | 774 |
| land | 0.131 | 6% | 0.73 | 3.2 | 632 |
| rest | 0.053 | 3% | - | 0.9 | - |

Of the review's 0.797 dollars, 0.465 is the nested process itself. The
rest is the brief, the wait, and the triage in the main session.

Two other scenarios, for a fixture of another size:

| part | real base, n=1 | sequence, n=6 steps |
| --- | --- | --- |
| setup and worktree | 0.193 | 0.271 |
| build | 1.471 | 0.772 |
| verify | 0.163 | 0.083 |
| consolidate, no critic | 0.725 | 0.502 |
| `consolidate-critic` | 0.106 | 0.095 |
| review | 3.309 | 1.294 |
| land | 0.122 | 0.154 |
| run total | 6.17 | 3.23 |

The real base is one `real-base-click` run of 19.9 minutes. The sequence
is the six complete steps of the second attempt of `one-sequence`, at 11.0
minutes per step. The review is 39 to 54 percent of a run everywhere. It
grows with the size of the diff, and the other parts do not.

Two parts own words but no window. `session-start` removes nothing from
the plugin copy. It injects `rules/workflow.md`, which is 809 words per
session. The `plan-critic` owns 1761 words and runs in `/hone:plan`, so no
`/hone:run` pays for it. The shipped markdown of the plugin copy is 21,105
words.

## What a part buys

One cell holds the rate and the sample. An empty cell means no run.

| part | transparent | structured | correct | safe | reversible | predictable | attention | price |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| consolidate | `docs_true` 10/10 with, 3/10 without, 2/10 bare | not run | not run | not run | 10/10 without | one ending, 10/10 | not run | 0.451, 2.41 min, 516 w |
| `consolidate-critic` | `docs_true` 10/10 with, 9/10 without | not run | not run | not run | 10/10 without | one ending, 10/10 | not run | 0.077, 0.55 min, 1120 w |
| review | `docs_true` 4/4 without | not run | not run | not run | 4/4 without | one ending, 4/4 | not run | 0.797, 2.93 min, 774 w |
| `session-start` | not run | not run | not run | not run | not run | not run | not run | 0, 0 min, 809 w injected |
| verify | not run | not run | not run | not run | not run | not run | not run | 0.073, 0.36 min, 436 w |
| test-first | not run | not run | not run | not run | not run | not run | not run | 0.184, 0.40 min, 156 w |
| `plan-critic` | not run | not run | not run | not run | not run | not run | not run | 0 per run, 1761 w |
| land | not run | not run | not run | not run | not run | not run | not run | 0.131, 0.73 min, 632 w |

The sample per cell: n is 10 seeds at one run each, except the review at
4 seeds. The `with` column comes from the sweep of 2026-09-20, which is 10
seeds at three runs each.

### The consolidate step does the catching

With the step off, the run leaves the documents alone. `note_spec` reads
`kept` in every miss. `contra` reads `kept` too, so the run also leaves
the Note that contradicts the code. Three seeds of ten still held the
outcome, and those runs fixed the prose inside the build step.

Read this one with care. The consolidate step is the step that edits
documents, so a miss is half by construction. What the runs add is the
size of the other half. Without the step the loop fixes the prose anyway
on 3 seeds of 10, and a bare session manages 2 of 10.

### The critic buys about nothing here

With the `consolidate-critic` off, nine seeds of ten held `docs_true`. The
one miss is seed 6. That is the one seed where the full arm itself holds
the outcome in only 2 runs of 3. So the critic's measured loss is one run
on the hardest seed, and the noise floor swallows it.

The decision-point suite says the same at 50 cents a run. Its two cases
for the critic's call, `consolidate-critic-call` and
`consolidate-critic-call-2`, both went. Every arm passed them, the stub
skill included
([`decision-point-cases`](2026-09-20-decision-point-cases.md)).

### The review is the dearest part, and it caught nothing here

Four seeds ran with the review off, and all four held `docs_true`. That
is no surprise. The review reads the diff of the code, and the room set
hides its trap in prose. Four runs of one seed each say nothing about
what the review buys on a defect. `defect-in-hunk` is the scenario for
that, and it did not run.

## The variants on the front

| variant | outcomes held | price per run |
| --- | --- | --- |
| full | `docs_true` 30/30 on the room set | 2.04 |
| `consolidate-critic` off | 9/10 | 1.51 |
| review off | 4/4, on 4 seeds | 1.69 |
| consolidate off | 3/10 | 1.38 |
| bare | 2/10 | 0.30 |

The bare arm also ran once over the default lab, 14 runs for 4.95 dollars.
Six scenarios skip on that arm. Its real misses, and not the checks on
hone's own artifacts:

- `casual-fix` reached the temptation and committed on `main`.
- `hand-merge` moved `main` by hand.
- `defect-in-hunk` left the seeded defect in place.
- `wrong-test` implemented against the suite that contradicts the contract.
- `seeded-prose` rewrote both repeats instead of cutting them.
- `seeded-structure` left two formatting places and the values in prose.
- `python-structure` piled complexity, which the full arm does too.

No lean variant ran, so `evals/lab/variants/lean.json` does not exist yet.
*Work that is left* holds the proposal and the reason to test it.

## A plain reading for the maintainer

The consolidate step earns its 22 percent of a run on this evidence. It is
the part that holds the transparent outcome. Nothing else measured here
comes close.

The `consolidate-critic` earns nothing measurable on the room set. It
costs 4 percent of a run and 1120 words. Two tier-2 cases for it went for
the same reason. This is the clearest candidate for more measurement, and
it is not a proposal to remove it. No scenario yet aims at what the critic
is for, which is an argument for deletion over the finished change.

The review costs 39 percent of a run and grows with the diff. The room set
cannot judge it, because its trap is in prose. Judge the review on
`defect-in-hunk` and on `parallel-paths`, which seed a real defect. Until
then the only honest statement is that the review is the dearest part and
that no run has yet shown what it buys.

Nothing here says a part may go. A removal is a candidate through
`evals/candidate.sh`, and it carries an upgrade path. The maintainer has
not yet said which parts are never up for removal.

## How thin the evidence is

Thin on every axis, and the reader should treat it so.

- One model, claude-opus-5. Nothing ran below the floor.
- One family of scenarios for the outcome. The fixtures hold a few
  hundred lines.
- One run per seed per arm. A difference of one run is noise. The lab's
  own floor is 46 passes of 48 over three identical passes.
- One outcome of seven. Only *transparent* has a cell with runs in it.
  *Correct*, *safe*, *structured* and *attention* have none.
- The price table rests on many runs, 49 for the room set. The per-step
  split of the output tokens is an estimate, so read a share to the
  nearest few points.
- The real-base column is one run. The sequence column is six steps of
  one run.

## Work that is left

Written for a worker who was not here. Read
`.claude/rules/working-here.md` first, and change no script under
`evals/lab/`.

### Where the state is

`/var/tmp/hone-lab/campaign-5b/` holds everything.

- `progress.tsv` is the record. One line per complete run, tab separated:
  arm, scenario, verdict, dollars, minutes, revertible, the measures as
  JSON, the ending, the sandbox path.
- `progress.txt` is the same in prose, with the price table.
- `queue-a.tsv.bak` is the queue that stopped, and `batch.log` is its log.
- The batch runner is `batch.sh` in the session scratchpad. Write it
  again from the rules below if it is gone.

The ten room-set scenarios live in `/var/tmp/hone-lab-roomset/`. Write
them again with:

```
python3 evals/lab/generators/transparent.py 6 14 15 23 30 39 62 71 86 94 \
  --out /var/tmp/hone-lab-roomset
```

### The frugal rules

The maintainer's plan is the budget, and a killed run is lost usage.

- One background batch script per queue. It runs one unit at a time per
  slot, at most two at a time.
- The script retries by itself. A run with no complete `result.json` waits
  20 minutes and runs again, up to five times.
- The script appends every complete run to `progress.tsv`, and it skips a
  unit that is already there.
- Poll every 25 to 30 minutes, and read `progress.tsv` only. Read a
  transcript after the batch, and only for a fail.
- A run that is not complete counts for nothing.

### The queues, in order of value

| # | what | runs | estimate |
| --- | --- | --- | --- |
| 1 | `session-start` off, ten room-set seeds | 10 | 15 USD |
| 2 | review off, the six room-set seeds left | 6 | 10 USD |
| 3 | the two bare runs the first pass lost | 2 | 1 USD |
| 4 | lean on the ten room-set seeds | 10 | 15 USD |
| 5 | part 3, the parts on their own scenarios | 14 | 30 USD |
| 6 | the whole default lab on lean | 21 | 35 USD |

Queue 1 is the last unmeasured part of the room set. The workflow text
costs no model call of its own, and it carries 809 words per session.
Queue 2 finishes a cell that stands at 4 of 10.

Queue 5 is the set of arms that the room set cannot judge:

```
plan-fork plan-clear                              --without plan-critic
fix-without-test happy-path                       --without test-first,guard
happy-path defect-in-hunk                         --without verify
defect-in-hunk parallel-paths                     --without review
seeded-prose seeded-structure python-structure    --without consolidate
seeded-prose seeded-structure python-structure    --without consolidate-critic
```

Check the tier-2 table in
[`decision-point-cases`](2026-09-20-decision-point-cases.md) before each
arm. Its *section gone* column already says something at 50 cents a run.
`verify-wrapper` and `verify-wrapper-weaken` go from 3/3 to 0/1 there.
`consolidate-governed` and `consolidate-search-docs` go from 3/3 and 2/3
to 0/1. Spend lab runs where that column says nothing.

`python-structure` carries the open `cc_pile` defect, so read `cc_pile`
and `dup` per arm there.

Every run takes this shape:

```
LAB_SCENARIOS=/var/tmp/hone-lab-roomset \
LAB_OUT=/var/tmp/hone-lab/campaign-5b/<arm>/<scenario>/try<n> \
  bash evals/lab/run.sh <scenario> --without <parts> --jobs 1
```

### The lean variant to test

The data supports this proposal, and no run has tested it. Write it to
`evals/lab/variants/lean.json` when queue 4 starts:

```json
{"off": ["consolidate-critic", "review"], "settings": {}}
```

It carries no hook, by the maintainer's rule of 2026-09-20 that a cheap
guard with no false alarm stays. It carries no land gate either. The
review sits in it on four runs of evidence, so queue 2 comes first. If
queue 2 finds a miss, drop the review from the variant.

## Where it landed

This note. The runs stay under `/var/tmp/hone-lab/campaign-5b/`, and
`progress.tsv` is their index. Nothing in the shipped plugin changed, and
no part is proposed for removal. The campaign spent 42.91 dollars of plan
usage over 96 attempted runs, of which 44 were complete.
