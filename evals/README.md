# Evals: pinning the judgment prose

The two critics and the `run` skill's loop instructions are behaviour-shaping
prose doing real judgment work, and unverified prose is the one part of hone's
trust foundation that can go stale silently: nothing type-checks a prompt. These
evals pin them to cases with known-good answers, so a reword that quietly weakens
a critic, or a cut that quietly drops a loop behaviour, is caught.

They are equally the licence to *delete*. As models improve, prose a prompt used
to need becomes prose the model no longer needs told, but which paragraphs those
are is empirical, not a matter of taste. Trim, re-run, keep what holds. Without a
suite, cutting a prompt is a guess about future behaviour.

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

Match the model to what actually runs in production, or the result means nothing:
the critics are pinned to `model: sonnet` in their frontmatter, while the `loop`
target is whatever model drives the session (`--model opus`).

## Targets and cases

*`plan-critic`*, verdict `APPROVE`/`REJECT`. REJECT cases, two per category:
`placeholder-tbd` and `placeholder-vague-proof`, `two-changes` and
`bundled-refactor` (scope), `collision` (shared files) and `slug-collision`,
`proof-altitude` and `ops-claim-unit-proof` (a user- or ops-level claim whose
only proof is a unit assertion), `prose-for-artifact` and
`prose-error-catalogue` (specific data spelled out in prose that a fixture
should carry instead), `dep-refresh-blind-latest` (a refresh Plan sweeping every
package to `latest`, so no one can say what it builds). APPROVE cases:
`clean-scoped`, plus the near-misses `cohesive-two-files` (tempts scope),
`named-references` (tempts missing-artifact), `adjacent-open-change` (tempts
collision), `dep-refresh-no-red-test` (a toolchain refresh with no red test and
its counts pinned as data, which tempts placeholder and proof-altitude).

*`consolidate-critic`*, verdict `CLEAN`/`CUTS`. CUTS cases, two per category:
`decision-restates-code` and `decision-narrates-diff`, `note-drift` and
`note-per-behaviour`, `single-caller-generic` and `wrapper-single-user`
(over-abstraction), `garden-stale-decision` and `garden-superseded-decision`
(Decisions a garden pass should cut). CLEAN cases: `lean-change`, plus the
near-misses `decision-carries-why` (tempts decision-restates-code),
`single-caller-helper` (tempts over-abstraction; rule of three, not rule of
one), `example-beside-property` (tempts redundant-test; example, property, and
golden tests are complementary).

*`loop`*, the next action `run` takes, one of `STOP SKIP DISCARD NEST RECORD
BACKGROUND ASK EXPAND HANDROLL PROCEED`: a claimed worktree under a single change
(STOP) and under `--all` (SKIP), a red test that passes on its first run and a
confirming test written after a fix (DISCARD), the `/code-review` refusal and the
subagent-fan-out temptation (NEST, not HANDROLL), a confirmed out-of-scope
finding, twice (RECORD, not EXPAND or ASK), exhausted verify and both land
gates (STOP), a suite and a mutation run outlasting the foreground timeout
(BACKGROUND), a mutation check with no critical path named (SKIP), a clean
review, a red test failing for the right reason, and a clean worktree claim
(PROCEED). The wrong tokens sit in the list on purpose: a case the skill fails
is one where its prose was carrying the behaviour and the model does not supply
it unprompted.

## Balance

Both critics' likely failure mode under prompt editing is *over-strictness*:
every hunting paragraph added makes them reject more, and the tie-break already
leans conservative. A suite of only REJECT/CUTS cases cannot see that drift; an
always-reject critic would score near-perfect. The near-miss cases exist for
exactly this: each one is built to tempt a specific rejection category while the
prompt's own calibration text says it must pass. A near-miss case going red
after a prompt edit means the edit made the critic stricter than its own rules.

## Held-out cases

Case dirs named `*-holdout` are skipped unless `--holdout` is passed. They are
the check against tuning to the suite: "trim, re-run, keep what holds" is
optimization against these cases, and prose can end up passing the briefs it was
trimmed against while the behaviour is gone in any paraphrase. So: never read a
holdout brief or edit prose with one in view; run `--holdout` once, as the last
check before a release. A holdout failure after a green main suite is the
overfitting signal, and the fix is the prose, never the holdout case.

## How a case is scored

Each case is `evals/<target>/<case>/` with a self-contained `brief.md` and an
`expected` file whose first line is the token and whose further lines are
substrings the reply must mention. The runner puts the prose under test in the
system slot (the agent body for a critic, `skills/run/SKILL.md` for the loop), the
brief in the user turn, calls `claude -p` headless, and takes the last token in
the reply as that run's answer. Every target's instruction demands an exact
final line (`ACTION:`/`VERDICT:`), so the extracted token is the stated answer,
not one the model happened to name last while reasoning.

Votes are scored by plurality, and `tokens_for` in `run.sh` lists each target's
tokens most-conservative-first, so a tie breaks toward the conservative one: a
split critic rejects, a split loop stops. The required substrings must appear in
a vote that carried the verdict; a losing vote mentioning the term proves
nothing about the judgment that won. A case where *every* vote failed to
answer is a loud FAIL, never a pass, so a dead harness cannot green the suite by
falling through to whichever token was expected.

Each result line carries its vote count (`ok  collision → REJECT (3/3)`, or the
split on a non-unanimous case). A pass at 2/3 is still a pass, but a case
drifting from unanimous to split across prompt edits is degrading; the tally is
where that shows before it flips.

Every `case × vote` call is independent and fans out concurrently, capped at
`--jobs`. `--votes` exists because these are borderline judgments with real
sampling variance. Raising `--jobs` is faster but can hit API concurrency limits
and error a call (which scores as no answer).

## Extending

Add a case whenever a critic misjudges a real change or the loop takes a wrong
turn: capture the brief that fooled it and the answer it should have reached. The
suite is the regression net for every future edit to a critic prompt, to the run
skill, or to the injected rule.
