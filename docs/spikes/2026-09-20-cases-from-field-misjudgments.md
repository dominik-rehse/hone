# Spike: eleven real critic misjudgments, turned into eval cases

**Date:** 2026-09-20 · **Status:** frozen. Written once, never maintained
against the code.

## Question

Step 2 of the handoff says that each real misjudgment of a critic becomes a
case. Two field reports list eleven of them, from real sessions in four
private repositories. How many survive as cases, and where does each go?

## What ran

I wrote one case per shape, fully redacted. Each case got a new domain, new
names, and new content. Two of the eleven share one shape, the cut outside
the change, so they became one case. That gives ten cases.

Every case ran on the shipped prompt at three votes, on claude-opus-5, and
then under `--ablate` at three votes. Where the stub agreed with the expected
answer, the case ran again against the second baseline. That is the prompt
minus the paragraph the case pins, as `evals/README.md` describes it.

All eleven field misjudgments happened on claude-sonnet-5. The shipped
critics pin claude-opus-5 today, so every tally below is a re-measurement of
the shape on a different model.

## Result

Five cases entered the suite. Two entered `evals/optimize/cases/`. Three
pinned nothing and I dropped them.

### Into the suite

| case | critic | expected | shipped | baseline |
| --- | --- | --- | --- | --- |
| `indexer-strips-only-copy` | plan | REJECT + `contradiction` | 3/3 | stub REJECT 3/3, never says the word |
| `invariant-overgeneralised` | plan | REJECT + `contradiction` | 3/3 | stub REJECT 3/3, never says the word |
| `tool-negative-from-config` | plan | REJECT + `contradiction` | 3/3 | stub REJECT 3/3, never says the word |
| `same-claim-two-layers` | consolidate | CLEAN | 3/3 | stub CLEAN 3/3; minus *Calibration* CUTS 3/3 |
| `ordered-deletion-not-in-diff` | consolidate | CUTS + `leftover` | 3/3 | stub CUTS 3/3, never says the word |

The shapes:

- `indexer-strips-only-copy`. Every claim the Plan makes is true, and the
  named mechanism still destroys data for one of the inputs the change runs
  over. The critic checked claims, not consequences.
- `invariant-overgeneralised`. Every file citation checks out, and the rule
  the Plan draws from them is false. The false rule was headed for a durable
  Note.
- `tool-negative-from-config`. The Plan asserts a negative about a
  third-party tool, backed only by a proxy signal in a config file. The
  critic accepted the proxy.
- `same-claim-two-layers`. Two tests assert one proposition at two layers.
  The critic read them as redundant, because it judged by the claim and not
  by the layer.
- `ordered-deletion-not-in-diff`. The Plan ordered a deletion that the diff
  does not show. The critic asserted the deletion had happened, inside a
  `CLEAN` verdict.

All three plan-critic cases pin a category word and not the verdict. The
stub rejects every flawed Plan tried so far, which the *Known gaps* section
already records. So the substring is the whole case in each, as it is for
`schema-silent-on-data`.

### Into `evals/optimize/cases/`

The shipped prompt fails both of these, so a suite that held them would be
red at every release.

| case | critic | expected | shipped |
| --- | --- | --- | --- |
| `stale-count-in-motive` | plan | APPROVE | REJECT 3/3 |
| `spike-pointer-to-deleted-plan` | consolidate | CLEAN | CUTS 3/3 |

- `stale-count-in-motive` is a petty reject. The only finding is a stale
  count in a motivating sentence, and the fixture file drives the build. The
  critic names it a `contradiction` in every vote of every run.
- `spike-pointer-to-deleted-plan` is a spike note whose forward pointer names
  two homes. One is a live Decision. The other is the Plan that consolidate
  deletes by design. The critic proposes to trim the dead half, which its own
  prose forbids: never propose to update a spike note.

Both went through two fairness rounds. A first draft of each carried a second
defensible objection. That made the expected verdict arguable, so I closed the
objection and measured again. Read the note on
[the second fork](2026-09-19-fork-case-second-fork.md) for the same
pathology found a day earlier.

### Dropped

| case | critic | expected | shipped | why |
| --- | --- | --- | --- | --- |
| `test-the-plan-called-critical` | consolidate | CLEAN | 3/3 | stub CLEAN 3/3, minus *Calibration* CLEAN 3/3 |
| `cut-outside-the-change` | consolidate | CLEAN | 2/3 | stub CLEAN 3/3, minus the reactive sentences CLEAN 3/3 |
| `safety-param-default` | consolidate | CLEAN | 3/3 | stub CLEAN 3/3, minus *Calibration* CLEAN 2/3 |

Each got one harder variant, and each still pinned nothing. The first shape is
a cut against the Plan's stated stance. The second is a cut outside the
change's diff. The third is a cut that gives a safety parameter a silent
default. The opus stub holds all three lines by itself, so hone's prose
changes no answer.

`safety-param-default` is the instructive one. It flipped between `CUTS` and
`CLEAN` three times as the brief changed. In the versions where the shipped
prompt failed, a second cut was arguably right, so the case was unfair. In
the version where the case is fair, the case pins nothing.

## What it means

The shape of a real misjudgment does not survive a model change. Five of the
ten shapes are gone on opus, and three of those five leave no trace the suite
can hold. That is the same finding the handoff records under *No headroom on
opus*, now measured on field data rather than on scenarios.

Two shapes still beat the shipped prompt. Both are calibration failures and
not blindness: the critic sees the right facts and then over-reaches. That is
the direction the search of step 6 should push.

## Cost

111 model calls on claude-opus-5, about 13.25 dollars of plan usage.

## Where it landed

`evals/plan-critic/`, `evals/consolidate-critic/`,
`evals/optimize/cases/`, and the case ledger in
[`evals/README.md`](../../evals/README.md).
