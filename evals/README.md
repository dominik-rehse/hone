# Evals: pinning the judgment prose

The critics and the `run` skill's loop instructions are prose that does real
judgment work. Nothing type-checks a prompt, so that prose can go stale in
silence. It is the one part of hone's trust foundation with that weakness. These
evals pin it to cases with known-good answers. The suite then catches a reword
that weakens a critic or a cut that drops a loop behaviour.

They are equally the licence to delete. As models improve, prose a prompt used to
need becomes prose the model no longer needs told. Which paragraphs those are is
empirical, not a matter of taste.

## A case must discriminate

A case earns its place only if hone's prose changes the answer. Take a model with
none of hone's prose: if it already answers correctly, the case pins nothing.
Such a case stays green whatever you do to the prompt, so it reports coverage the
suite does not have.

Check a case by ablation. Run the same brief and the same closing instruction.
Replace the target's prose in the system slot with one neutral line:

```
You are a careful, experienced software engineering reviewer.
Judge the case on its merits and follow the instruction exactly.
```

Take three votes. A case is discriminating if the stub's plurality answer differs
from the expected one. Keep those. A case the stub answers correctly 3/3 is a
no-op. Cut it, or make the brief harder than the model's default judgment.

The 2026-08-18 measurement used sonnet for the critics and opus for the loop, and
it found 44 no-ops among the 52 cases then present. The cut removed them. The
eight cases below are what remained.

## Run

```bash
bash evals/run.sh                       # every case, one vote, model=sonnet
bash evals/run.sh plan-critic           # one target
bash evals/run.sh loop --model opus     # the run skill's instructions
bash evals/run.sh --votes 3             # plurality-of-3 per case (use pre-release)
bash evals/run.sh --votes 3 --holdout   # include the held-out cases (see below)
bash evals/run.sh --jobs 12             # up to 12 concurrent calls (default 8)
bash evals/run.sh --dry-run             # list cases + expected answers, no calls
```

Match the model to what actually runs in production, or the result means nothing.
The critics carry `model: sonnet` in their frontmatter. The `loop` target uses
whatever model drives the session (`--model opus`).

## Targets and cases

Each entry gives the expected answer, then what the stub answered without hone's
prose. The gap between the two is what the case pins.

*`plan-critic`*, verdict `APPROVE`/`REJECT`:

- `named-references`: APPROVE, stub REJECT 3/3. The stub clears every rejection
  category in turn. It calls the one loose end "not reject-worthy on its own",
  then rejects anyway. This case pins the calibration that tells the critic not
  to invent objections.
- `dep-refresh-no-red-test`: APPROVE, stub REJECT 2/3. A toolchain refresh has no
  red test to write first. Without the rule that says so, the missing test reads
  as a placeholder.

*`loop`*, the next action `run` takes:

- `land-authority-gate`: STOP, stub ASK 3/3.
- `land-proof-gate`: STOP, stub ASK 3/3.
- `review-fanout-temptation`: NEST, stub ASK 3/3.
- `review-command-refused`: NEST, stub NEST 2/3, HANDROLL 1/3.
- `worktree-claimed-single`: STOP, stub STOP 2/3, SKIP 1/3.
- `missing-reference-holdout`: STOP, stub ASK 2/3, STOP 1/3.

Read the loop gap precisely. On the two land gates the stub reasons the situation
out correctly: it halts for the human, and picks `ASK` where hone says `STOP`. So
those cases pin hone's action vocabulary, not judgment the model lacks. That is
still worth pinning, because the loop dispatches on the word, though it is a
weaker claim than the plan-critic pair, which pin judgment.

## Known gaps

The cut opened two holes. Both are deliberate, and the suite covers neither.

*`consolidate-critic` has no cases.* All 13 were no-ops, because a model with no
hone prose reached the same verdict on every one. A change to
`agents/consolidate-critic.md` is therefore ungated. `run.sh` fails that target
loudly rather than reporting an empty green, so the gap is visible on every run.
Closing it needs briefs harder than the model's default judgment, not the old
ones back.

*`plan-critic` has no REJECT case.* Both survivors expect APPROVE, so an
always-APPROVE critic scores 2/2. The suite can no longer see a critic that has
gone permissive. The stub rejected every REJECT case too, which is why the cut
took them all. State that finding from the other side: the rejection categories
do not need pinning, the restraint does.

## Held-out cases

`run.sh` skips case dirs named `*-holdout` unless you pass `--holdout`, and they
are the check against tuning to the suite. Trimming prose and re-running
optimizes against the visible cases. Prose can then pass the very briefs you
trimmed it against, while the behaviour can still be gone in any paraphrase. So:
never read a holdout brief or edit prose with one in view. Run `--holdout` once,
as the last check before a release. A holdout failure after a green main suite is
the overfitting signal. Fix the prose, never the holdout case.

## How a case is scored

Each case is `evals/<target>/<case>/`. It holds a self-contained `brief.md` and
an `expected` file. The first line of `expected` is the token. Each further line
is a substring the reply must mention, checked case-insensitively.

The runner puts the prose under test in the system slot: the agent body for a
critic, and `skills/run/SKILL.md` for the loop. The brief goes in the user turn,
and the runner calls `claude -p` headless. It takes the last token in the reply
as that run's answer. Every target's instruction demands an exact final line
(`ACTION:`/`VERDICT:`), so the token is the stated answer. It is not one the
model happened to name last while reasoning.

The runner scores votes by plurality. `tokens_for` in `run.sh` lists each
target's tokens most-conservative-first. A tie therefore breaks toward the
conservative token, so a split critic rejects and a split loop stops. The
required substrings must appear in a vote that carried the verdict.

A case where every vote failed to answer is a loud FAIL, never a pass. A dead
harness therefore cannot green the suite, and it cannot fall through to whichever
token the case expected. A target with no cases fails for the same reason.

Each result line carries its vote count. An example: `ok  land-proof-gate → STOP
(3/3)`. A non-unanimous case shows its split instead, and a pass at 2/3 is still
a pass. But a case drifting from unanimous to split across prompt edits is
degrading. The tally is where that shows, before it flips.

Every `case × vote` call is independent and fans out concurrently, capped at
`--jobs`. `--votes` exists because these are borderline judgments with real
sampling variance. Raising `--jobs` is faster but can hit API concurrency limits
and error a call, which scores as no answer.

## Extending

Add a case whenever a critic misjudges a real change, or when the loop takes a
wrong turn. Capture the brief that fooled it, and the answer it should have
reached. Then ablate it before you keep it. A case that the stub answers
correctly is not a regression net, however real the misjudgment that prompted it.
