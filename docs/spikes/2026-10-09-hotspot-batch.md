# Spike: a coordinated batch that split ten complexity hotspots

**Date:** 2026-10-09 · **Status:** frozen. Written once, never maintained
against the code.

## Question

[The note on function complexity](2026-10-09-function-complexity-in-the-field.md)
found that runs pile complexity into long functions. Can hone's loop take
the worst of these functions apart again, unattended, without a change of
behavior? And what goes wrong in a batch on 0.78.1?

## Method

The maintainer's session picked ten hotspots in four private consumer
repositories. A hotspot is a function with a high cognitive complexity in a
file that changed often. It started one `/hone:coordinate` session per
repository in herdr, with one request: plan and run one change per function, and split
it along its cases with no change of behavior. The request said that the
person accepts every Plan the `plan-critic` approves. A watcher read the
herdr pane states every minute. I measured each function with cccc 1.8.0 on
`main` after its land. The batch ran from 20:55 to about 23:30.

## Results

| function | before | after | highest in the file after |
| --- | --- | --- | --- |
| an anonymous route handler | 82 | 15 or less | 15 |
| `writeIngest` | 64 | 5 | 13 |
| `runIndex` | 47 | 13 | 15 |
| `runDraft` | 41 | 5 | 7 |
| `runLoop` | 40 | 6 | 20 |
| `convertTree` | 40 | 1 | 14 |
| `parseConvertArgs` | 34 | 12 | 24 |
| `fillBrief` | 31 | 1 | 11 |
| `drain` | 31 | 6 | 7 |
| `confirmWrite` | 29 | 2 | 3 |

- All ten landed. A file's highest score above 15 belongs to an older
  function that the batch did not touch. The anonymous handler has no name
  that survives a split, so its row gives the highest score in its file.
- Several runs added characterization tests before the split. One run
  found and fixed an older defect in a proof test, in a commit of its own.
- One land needed the person's real-environment sign-off. The run did not
  run the check itself, because the check writes into a real mailbox.
- `worktree.sh hygiene` and `worktree.sh attention` reached the reports.
  Three runs named an area over the 3000-line cap for the person.
- Three batch consolidate passes cut nothing. The fourth found a redundant
  test.

What went wrong:

- One "no change of behavior" split changed behavior. An action of an
  unknown kind now throws, where before it counted as a revert. The type
  checker keeps such a value out. The run reported it, and the person
  decides.
- `coordinate.sh start` typed one run's prompt into its tab and did not
  submit it. The coordinator asked the person to press Enter.
- One coordinator ended its turn twice with no wait, and the watch hook let
  it end. A watched run then had nobody to wake.
- The first `wait` of two coordinators printed events of earlier batches.
  One progress line named a consolidate change of an earlier pass.
- In one repository, three parallel runs queued on the suite lock. One
  verify timed out twice at 600 seconds (exit 5), and the run wrote its own
  retry loop.
- One coordinator reported the scores from the commit messages and did not
  measure them. The other three measured.

## What follows

- A split of a long function is a good unattended change: small, proven by
  the existing tests, and cheap to review. `/hone:garden` now proposes
  such Plans from `worktree.sh hotspots`.
- The behavior change shows that "no change of behavior" is a claim the
  loop does not check. Only the tests check it.
- The coordinator defects are field-log lines with the date of this note.
