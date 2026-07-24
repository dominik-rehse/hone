# Evals — pinning the judgment prose

The two critics and the injected `rules/workflow.md` are behaviour-shaping prose
doing real judgment work, and unverified prose is the one part of hone's trust
foundation that can rot silently. These evals pin them to cases with known-good
verdicts, so a reword that quietly weakens a critic is caught.

## Run

```bash
bash evals/run.sh                       # every case, one vote, model=sonnet
bash evals/run.sh plan-critic           # one critic
bash evals/run.sh --votes 3             # majority-of-3 per case (use pre-release)
bash evals/run.sh --jobs 12             # up to 12 concurrent calls (default 8)
bash evals/run.sh --dry-run             # list cases + expected verdicts, no calls
bash evals/run.sh --model opus          # override the judge model
```

Each case is `evals/<critic>/<case>/` with a self-contained `brief.md` (the
constructed context the loop would hand the critic) and an `expected` file whose
first line is the verdict token (`ADMIT`/`REJECT`, or `CLEAN`/`CUTS`) and whose
further lines are substrings the findings must mention. The runner puts the
agent's own body in the system slot (as a real subagent runs it) and the brief in
the user turn, calls `claude -p` headless, and compares.

Every `case × vote` call is independent, so they fan out concurrently, capped at
`--jobs`. A full `--votes 3` sweep (24 calls) lands in ~90s at 8-way concurrency
instead of the ~8 minutes it would take one at a time. `--votes` exists because
these are borderline judgments with real sampling variance; a majority makes a
pass trustworthy. Raising `--jobs` is faster but can hit API concurrency limits
and error a call (which scores as an empty verdict).

## Cases

`plan-critic`: `clean-scoped` (ADMIT), `placeholder-tbd`, `two-changes`
(scope), `collision`, `proof-altitude` (a user-level claim whose only proof is a
unit assertion). `consolidate-critic`: `lean-change` (CLEAN),
`decision-restates-code`, `note-drift`, `single-caller-generic`
(over-abstraction), `garden-stale-decision` (a Decision whose governed code is
gone, surfaced by a garden pass).

## Extending

Add a case whenever a critic misjudges a real change: capture the brief that
fooled it and the verdict it should have reached. The suite is the regression net
for every future edit to a critic prompt or to the rule.
