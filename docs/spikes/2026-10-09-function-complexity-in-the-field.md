# Spike: function complexity in the field

**Date:** 2026-10-09 · **Status:** frozen. Written once, never maintained
against the code.

## Question

The lab scenario `python-structure` showed a run that puts a heavy new case
inline into a function that is already long
([`python-structure-baseline`](2026-09-19-python-structure-baseline.md)).
Does the same happen in real use? And is cccc, a complexity tool for many
languages, a fit for a check?

## Method

I scored four private consumer repositories with cccc 1.7.0. All four are
TypeScript, and all four lint with Biome 2.5.8. The measure is the
cognitive complexity of SonarSource, per function. The threshold is 15,
the default of SonarSource and of Biome.

For each named function outside the tests that scored over 15 at `HEAD`, a
script walked the first-parent history of `main` that touched the file. It
scored the function at each commit and gave each change in score to the
step that landed it. A step is a merge of a `hone/` branch, or a direct
commit. The script matches a function by file and name, and it does not
follow a rename. So a function that a move-only run relocated shows up as
new in that run, and the script loses its history before the move. The counts below
leave those moves out.

## Results

Growth of functions that already existed before the step:

| repository | hone merges | of them +10 or more | crossings of 15 | direct commits |
| --- | --- | --- | --- | --- |
| 1 | +108 in 22 steps | 3 | 4 | +0 |
| 2 | +54 in 12 steps | 0 | 2 | +142, 7 crossings |
| 3 | +47 in 12 steps | 1 | 4 | +4 |
| 4 | +121 in 30 steps | 3 | 5 | +22 |

- Every direct commit that grew one of these functions predates hone in
  its repository. Since hone came in, the functions grew only through hone
  runs.
- hone runs also wrote 16 functions that scored over 15 from their first
  commit.
- hone runs shrank a function in 11 steps, by 52 points together. One
  run took a function from 52 to 30.
- The three largest jumps: 3 to 35 in one run, 20 to 39 in one run, and
  32 to 47 in one run. The first and the third came on 2026-09-28, under
  hone 0.65 to 0.67. The growth spans hone 0.2.0 to 0.75.0.
- At `HEAD` the largest function in each repository scores 40, 52, 64, and
  94.

## cccc as a tool

- Speed: 0.05 s for 345 files and 12,319 functions.
- Correctness: on the `python-structure` seed it gives `apply_movement`
  cyclomatic 7, as radon does. A hand count of one TypeScript function by
  SonarSource's rules gave 20, as cccc does. Biome gave 27.
- On the fixture, cognitive complexity separates the outcomes more widely
  than cyclomatic. The seed scores 11. The reasonable change, with a new
  function for the new kind, scores 12 and 12. The same kind inline scores
  30. Cyclomatic gives 7, 8 and 8, and 15.
- On a breach cccc exits 1 and names no function. `--min N --table`
  names it.
- A file that does not parse passes a threshold with exit 0 and a warning.
- It reports where a function starts and not where it ends, and it has no
  baseline mode. It reads no shell.

## What follows

- The pile-up of the lab happens in real use, in every repository, and it
  still happens under recent versions.
- Biome already has the check (`noExcessiveCognitiveComplexity`), and it
  was off in all four repositories. A plain threshold would fail at once on
  the existing functions, so a consumer needs it scoped to what a change
  touched.
- A ratchet can score the changed files on the base and on the branch,
  and match functions by file and name. It needs no end line, and old
  debt passes.
