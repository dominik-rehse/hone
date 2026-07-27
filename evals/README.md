# Evals: pinning the judgment prose

The two critics and the `run` skill's loop instructions are behaviour-shaping
prose doing real judgment work, and unverified prose is the one part of hone's
trust foundation that can go stale silently: nothing type-checks a prompt. These
evals pin them to cases with known-good answers, so a reword that quietly weakens
a critic, or a cut that quietly drops a loop behaviour, is caught.

They are equally the licence to *delete*. As models improve, prose a prompt used
to need becomes prose the model no longer needs told — but which paragraphs those
are is empirical, not a matter of taste. Trim, re-run, keep what holds. Without a
suite, cutting a prompt is a guess about future behaviour.

## Run

```bash
bash evals/run.sh                       # every case, one vote, model=sonnet
bash evals/run.sh plan-critic           # one target
bash evals/run.sh loop --model opus     # the run skill's instructions
bash evals/run.sh --votes 3             # plurality-of-3 per case (use pre-release)
bash evals/run.sh --jobs 12             # up to 12 concurrent calls (default 8)
bash evals/run.sh --dry-run             # list cases + expected answers, no calls
```

Match the model to what actually runs in production, or the result means nothing:
the critics are pinned to `model: sonnet` in their frontmatter, while the `loop`
target is whatever model drives the session (`--model opus`).

## Targets and cases

*`plan-critic`* — verdict `APPROVE`/`REJECT`: `clean-scoped` (APPROVE),
`placeholder-tbd`, `two-changes` (scope), `collision`, `proof-altitude` (a
user-level claim whose only proof is a unit assertion), `prose-for-artifact` (a
file format spelled out in prose that a fixture should carry instead).

*`consolidate-critic`* — verdict `CLEAN`/`CUTS`: `lean-change` (CLEAN),
`decision-restates-code`, `note-drift`, `single-caller-generic`
(over-abstraction), `garden-stale-decision` (a Decision whose governed code is
gone, surfaced by a garden pass).

*`loop`* — the next action `run` takes, one of `STOP SKIP DISCARD NEST RECORD
BACKGROUND ASK EXPAND HANDROLL PROCEED`: a claimed worktree under a single change
(STOP) and under `--all` (SKIP), a red test that passes on its first run
(DISCARD), the `/code-review` refusal (NEST, not HANDROLL), a confirmed
out-of-scope finding (RECORD, not EXPAND or ASK), exhausted verify and both land
gates (STOP), a suite outlasting the foreground timeout (BACKGROUND), a mutation
check with no critical path named (SKIP), and a clean review (PROCEED). The wrong
tokens sit in the list on purpose: a case the skill fails is one where its prose
was carrying the behaviour and the model does not supply it unprompted.

## How a case is scored

Each case is `evals/<target>/<case>/` with a self-contained `brief.md` and an
`expected` file whose first line is the token and whose further lines are
substrings the reply must mention. The runner puts the prose under test in the
system slot (the agent body for a critic, `skills/run/SKILL.md` for the loop), the
brief in the user turn, calls `claude -p` headless, and takes the last token in
the reply as that run's answer.

Votes are scored by plurality, and `tokens_for` in `run.sh` lists each target's
tokens most-conservative-first, so a tie breaks toward the conservative one: a
split critic rejects, a split loop stops. A case where *every* vote failed to
answer is a loud FAIL, never a pass, so a dead harness cannot green the suite by
falling through to whichever token was expected.

Every `case × vote` call is independent and fans out concurrently, capped at
`--jobs`. `--votes` exists because these are borderline judgments with real
sampling variance. Raising `--jobs` is faster but can hit API concurrency limits
and error a call (which scores as no answer).

## Extending

Add a case whenever a critic misjudges a real change or the loop takes a wrong
turn: capture the brief that fooled it and the answer it should have reached. The
suite is the regression net for every future edit to a critic prompt, to the run
skill, or to the injected rule.
