# Spike: can a generated scenario give the transparent outcome room?

**Date:** 2026-09-20 · **Status:** frozen. Written once, never maintained
against the code.

## Question

HANDOFF step 4 asks for room on *transparent*, where claude-opus-5 passes
every scenario of today. `seeded-prose` and `untied-sentence` are the two
scenarios of that outcome. Can one generator write scenarios of that family
that the model does not pass?

## What I did

`evals/lab/generators/transparent.py` writes a scenario from a seed number.
Its header has the parameters and the usage. Four parameters:

- the language of the fixture: javascript or python
- the domain: shipping, retention, ratelimit, cache, or payroll
- the place where the repeat hides. It is the governed Note, the Note of the
  neighbouring area, or a Decision with no `Governs:` line. It is also a table
  row in a README, or a header comment in a source file.
- the format of the repeat. It is the number as the code holds it, or the same
  value in another unit. It is also the value spelled out in words, or a
  consequence of the value with no number at all.

Every fixture carries two distractors and four unrelated Decisions with
numbers of their own. The lab runs a generated scenario unchanged, through
`LAB_SCENARIOS`. The plumbing test is in `test/lab_test.sh`.

Each instance ran on claude-opus-5, with hone and on the bare arm. The goal
`docs_true` is the outcome. It is `yes` when no document states the old value
as today's rule. The bare arm fails the verdict by construction, because it
lands no merge and runs no review, so the measure decides and not the verdict.

## Attempt 1: the value is in the document, in some form

Three instances, three runs with hone and three runs bare. The bare arm lost
six runs to the plan limit, and one complete bare run per instance remains.

| instance | place | format | hone: `docs_true` | bare: `docs_true` |
| --- | --- | --- | --- | --- |
| shipping | governed Note | literal | yes 3 of 3 | yes 1 of 1 |
| ratelimit | untied Decision | words | yes 3 of 3 | yes 1 of 1 |
| payroll | header comment | unit | yes 3 of 3 | yes 1 of 1 |

No room. The two arms agree on the outcome. A plain session with no hone
finds the sentence and updates it, in every place and in every format. The
fixture is a hundred lines, so reading every document is cheap, and the
converted and spelled-out forms did not hide anything.

With hone the run cut the sentence, and bare it rewrote the value. That is a
difference in habit, and it is not a difference in the outcome.

Cost: 9 runs with hone at 1.72 to 2.28 dollars, and 9 bare runs at about 0.28.
About 24 dollars in all, with the nested review counted.

## Attempt 2: the value is not in the document at all

Two changes to the generator. A fourth format, `derived`, states a consequence
of the value and no form of the number. So 90 days of retention reads as a
digest of 13 weeks. A line at 40 hours reads as a five-day week of eight-hour
days. Four unrelated Decisions with numbers of their own went into every
fixture. A search on a number now returns hits that a run must read and
reject.

| seed | instance | place | hone: `docs_true` | bare: `docs_true` |
| --- | --- | --- | --- | --- |
| 6 | retention, 13 weeks | untied Decision | yes 2 of 3 | no 3 of 3 |
| 14 | payroll, eight-hour days | neighbour Note | yes 3 of 3 | no 3 of 3 |
| 7 | ratelimit, one poll a second | README row | yes 4 of 4 | no 2 of 4 |

Room, of both kinds.

The arms differ. The bare arm left the false sentence standing in 8 of its 10
runs. It has no consolidate step, and a search for the number finds nothing.
Its two hits are the README row, which sits beside the code it changed.

The hone arm itself fails. In the retention instance one run of three left the
sentence standing. That run edited the very Decision that holds it, and added
a paragraph about the published notice. It cut the Behaviour list of the Note.
It fixed the Note that contradicted the code, and it fixed the stale Decision.
Then it left "The digest covers 13 weeks at most", which 180 days makes false.
The sandbox has the file and the `checks.log`. A careful engineer gets this
right, because 13 weeks is 91 days and the new age is 180 days.

Two runs answered the README row by deleting the README. That is a heavy
answer, and the check reads it as `gone` and not as a false sentence. A README
table that restates the code is a repeat, so the deletion is defensible.

Cost: 38 runs over both attempts, 53 dollars in all. A run with hone costs
about 2 dollars and 10 minutes, and a bare run about 0.30.

One fixture defect showed up, and the generator now avoids it. The Python seed
did not resolve its test dependency. So the first call of the adapter wrote
`uv.lock` into the primary tree, and `revertible` read that as a dirty tree.
The seed now runs `uv sync`, as the seed of `python-structure` does.

## Finding

The transparent outcome has room where the false sentence carries no form of
the number. Where it carries the number, in any unit and in any wording, both
arms hold the outcome and the scenario pins nothing. So `derived` is the
parameter that makes this family worth running, and the other three formats
are the easy end of it.

The place matters less than the format. A neighbour Note, an untied Decision,
a README row and a header comment all came out alike in attempt 1. The one
instance that broke the hone arm is an untied Decision, and one run of three
is a thin sample. Run more seeds of the `derived` format before you trust the
ranking of the places.

Attempt 1 ran before the `derived` format and the noise Decisions existed. Its
seeds now map to a slightly different format, so read its rows by the
parameters in this table and not by the seed number.

## Where it landed

`evals/lab/generators/transparent.py`, with the parameters in its header.
`test/lab_test.sh` proves the plumbing. HANDOFF step 4 carries the family, and
step 5 can use these instances as an axis for *transparent*.
