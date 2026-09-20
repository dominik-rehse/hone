# Spike: can harder fixtures make the review bench tell two reviewers apart?

**Date:** 2026-09-20 · **Status:** frozen. Written once, never maintained
against the code.

## Question

On the first bench, opus and sonnet each caught all 21 planted defects
([`review-bench-first-run`](2026-09-19-review-bench-first-run.md)). So the
bench could not compare two reviewers or judge a change to the review step.
Do larger fixtures with subtler defects give it headroom?

## What was built

A fixture is now a directory with a base project and two overlays on it.
One overlay is the change with the planted defect. The other is the same
change done right. The
pair yields two targets, so each defect has a clean twin that counts false
alarms. A prove script per defect fails on the defect variant and passes on
the clean twin, and the seeder runs it.

- Eight pairs with one defect each. The base has 400 to 570 lines, and the
  change 150 to 250. No comment, test name, or Plan sentence states the
  contract that the defect breaks. The contract is visible only in a file
  that the change does not touch. Each change carries decoys.
- Three fixtures with three defects each, in three files of one change. The
  base has 650 to 800 lines, and the change 310 to 350.

All reviews ran on claude 2.1.278 with the run skill's own command at level
`high`. Configuration A is claude-opus-5, and B is claude-sonnet-5. Each
target got three votes.

## Catches

| fixtures | chances per model | opus | sonnet |
| --- | --- | --- | --- |
| eight pairs, one defect each | 24 | 24 | 24 |
| three fixtures, three defects each | 27 | 27 | 24 |

The three misses of sonnet are one defect, 3 reviews of 3, and they
reproduced after the fixture was fixed. The change adds a field to a flag,
and an untouched serializer writes a fixed list of fields. So the field is
lost on save and restore. No review of sonnet opened the serializer. Every
review of opus did. One catch of opus was a miss by regex only, and a
`judged.json` corrects it.

A pilot with a comment that stated the contract was caught 3 of 3. Without
the comment it was still caught 3 of 3. A project of 500 lines is small
enough that a reviewer reads all of it.

## False alarms on the clean twins

An agent judged every finding on a clean twin by the rule in the header of
`grade.sh`. A finding is a false alarm, a remark that is not presented as a
defect, or a true finding about the fixture.

| pass | twins | model | findings per review | false alarms per review |
| --- | --- | --- | --- | --- |
| first, 2026-09-19 | 8 single | opus | 1.75 | 0.13 |
| first, 2026-09-19 | 8 single | sonnet | 3.75 | 3.0 |
| second, 2026-09-20 | 8 single | opus | 3.46 | 1.21 |
| second, 2026-09-20 | 8 single | sonnet | 3.25 | 2.83 |
| second, 2026-09-20 | 3 multi | opus | 5.2 | 4.89 |
| second, 2026-09-20 | 3 multi | sonnet | 5.2 | 5.22 |

sonnet files almost every finding as a defect. opus marks many of its
findings as remarks. On the multi twins both models sit near five false
alarms per review. Most of them ask for something that the Plan defers by
name, such as aging, atomicity, or more validation.

## The review of opus changed between the two passes

The same twins, the same command, and the same version of Claude Code gave
different reviews on the two days. In the first pass an opus review of a
single twin took 35 seconds and 0.23 dollars. In the second pass it took
151 seconds and 0.60 dollars. A repeat of two untouched twins on 2026-09-20 gave
61 to 159 seconds and 0.35 to 0.57 dollars. One review used 5,177 output
tokens where its twin of the day before had used 1,928. The reviews of
sonnet did not move. We do not know the cause.

So the rise of opus from 0.13 to 1.21 false alarms per review has three
possible sources, and this spike cannot separate them:

- the longer reviews
- a second judge with no calibration against the first
- the fixture fixes

## True findings about the fixtures

Reviews of clean twins found real weaknesses in the fixtures. 15 were fixed
during the build, and seven more after the first pass. After the second
pass six remain:

- `unit-mismatch`: no test makes the cap in `touch` bind. The tests stay
  green with the cap removed.
- `unit-mismatch`: no test runs a second `sweep()`, which the Plan names.
- `tz-boundary`: no test pins the path through `createInvoice` and `dueOn`.
  The tests stay green with the guard on the terms removed.
- `sorted-invariant`: no test notices when `merge.js` stops copying a slot,
  and a change to a merged slot then writes through to the input.
- `memo-key`: no test takes the owner path through `api.saveDoc` and
  `openDoc`.
- `flag-rollout`, clean twin: `isOn(key, null)` throws a `TypeError` on a
  flag with a rollout. The base never read the context.

## What it means

- The bench now separates the two models. sonnet misses an omission in an
  untouched file, and it files more false alarms on single twins.
- The bench still has almost no headroom on opus: 51 catches of 51. It
  cannot yet judge a change that should make the opus review catch more. It
  can judge a change that should make it raise fewer false alarms, once the
  count is stable.
- The count of false alarms is not stable yet. It needs a fixed judge, more
  than three votes, and an explanation for the change of opus between the
  days.

The two passes cost 43.7 dollars of reviews, and the pilots and builds about
25 more.

## Where it landed

`evals/probes/review-bench/`, fixtures under `fixtures/`.
[`roadmap.md`](../roadmap.md) carries what is open.
