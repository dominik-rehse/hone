# Spike: what does `scb-check` say about the code that hone lands?

**Date:** 2026-09-19 · **Status:** frozen. Written once, never maintained
against the code.

## Question

The goal *well structured* had no exact measure. `scb-check` is exact, but
it reads Python alone, and every lab fixture was JavaScript. Does a Python
scenario with `scb-check` as its measure tell a good run from a lazy one?

## What ran

The lab scenario `python-structure`. Its seed holds two pasted copies of a
formatting block, and one function `apply_movement` that handles every
movement kind inline. The Plan adds a third document and one more kind. Two
measures come from `uvx scb-check==0.1.3 check --report --include-all src`:

- `dup` reads `clone_loc`. It is `gone`, `kept`, or `grown`.
- `cc_pile` reads `high_cc_functions`. It is `flat` or `piled`. The tool
  counts a function over cyclomatic complexity 10.

Seven end states, built by hand, show that both measures move and that they
move independently. `uvx radon cc -s src` gave the complexity per function,
because `scb-check` has no such view.

## The first design was unfair

The first seed had two kinds, and the Plan added a third with three rules.
Three runs on claude-opus-5 passed with `dup gone` and `cc_pile piled`. An
agent then read the landed code. `apply_movement` had 35 to 37 lines, nesting
depth 3, and complexity 12 to 15. It was a flat dispatch over three kinds,
and no careful reviewer would ask for a split. The seed was tuned to the
tool's line and not to real badness. So `piled` punished reasonable code.

## The second design

The seed now has four kinds inline, 64 lines, complexity 7. The write-off
carries several lines, and all of them are validated before any stock moves.
So the inline version needs a loop with nested checks in a fifth branch.

| end state | `clone_loc` | `apply_movement` | `dup` | `cc_pile` |
| --- | --- | --- | --- | --- |
| seed | 16 | CC 7, 64 lines | kept | flat |
| lazy: pasted copy, fifth branch inline | 24 | CC 15, 87 lines | grown | piled |
| one function per kind, shared helper | 0 | CC 6, 15 lines | gone | flat |
| only the new kind in its own function | 0 | CC 8, 66 lines | gone | flat |

The last row is the smallest reasonable change. It scores `flat` with two
points of margin.

## Result on claude-opus-5, three runs

All three passed, at 2.00 to 3.99 dollars and 8 to 10 minutes.

- `dup gone` in 3 of 3. The builder extracted the shared helper at the third
  use, in the refactor step, without a prompt from the review. The same held
  in the three runs of the first design.
- `cc_pile piled` in 3 of 3. Each run put the write-off inline. The landed
  `apply_movement` had 78 to 87 lines and complexity 14 to 16. No run
  extracted a helper, so the measure read each run correctly.
- Nobody mentioned the size. The builder did not, the nested code review
  found behavior bugs only, and the `consolidate-critic` spoke about
  Decisions and tests.

A reviewer who read the landed code said that they would send it back, and
that the write-off branch is the obvious extraction.

## What it means

The rule of three works on Python. Nothing in hone works against
complexity that piles up in one function, and the review does not raise it.
That is the first measured gap for *well structured*. The measure that a
candidate needs now exists.

The first call of the test adapter in a run needed no network and lost no
time. hone's `scripts/setup.sh` adds neither `.venv/` nor `__pycache__/` to
`.gitignore` in a Python project. The scenario's seed does that itself.

## Where it landed

`evals/lab/scenarios/python-structure/`. [`roadmap.md`](../roadmap.md) carries
the gap.
