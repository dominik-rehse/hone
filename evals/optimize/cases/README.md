# Cases the shipped prompt fails today

Every case here has the layout of a suite case: one directory per case, with a
self-contained `brief.md` and an `expected` file. `evals/run.sh` does not read
this directory, and no release gate does either.

These cases are in no suite because the shipped prompt answers them wrong. A
suite that held them would be red on every release, and a red gate says
nothing. The search of step 6 in `HANDOFF.md` trains on them instead. A failure
is what a reflective optimizer learns from, so a case the prompt already passes
carries no signal for it.

A case leaves this directory when a shipped prompt passes it three votes of
three. Then it goes through the same admission check as any case:
`evals/README.md`, *A case must discriminate*. It enters `evals/<target>/` only
if it discriminates against a baseline.

Each case here is fair. A reasonable expert reader reaches the expected verdict
from the brief alone. Check that again before you train on a case, because a
brief with a second defensible reading teaches the wrong lesson.
