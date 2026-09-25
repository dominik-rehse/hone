# Evals: pinning the judgment prose

The critics and the `run` skill's loop instructions are prose that does real
judgment work. Nothing type-checks a prompt, so that prose can go stale in
silence. It is the one part of hone's trust foundation with that weakness. These
evals pin it to cases with known-good answers. The suite then catches a reword
that weakens a critic or a cut that drops a loop behavior.

They are also what makes deleting safe. As models improve, prose a prompt
used to need becomes prose the model no longer needs. Which paragraphs those
are is an empirical question, not a matter of taste.

## A case must discriminate

A case belongs in the suite only if hone's prose changes the answer. Take a model with
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

`--ablate` runs exactly that swap, keeping the brief and the closing instruction
identical:

```bash
bash evals/run.sh garden --votes 3 --model opus --ablate
```

Read its output backwards. A `FAIL` line is a case that discriminates, and an
`ok` line is a case that pins nothing.

### The stub only means something in isolation

The ablation asks what the model answers with **none** of hone's prose. So the
call must not be able to reach that prose. `run.sh` runs every call from an
empty directory, under `--safe-mode`, with every file, shell, and network tool
denied. `call_one` carries the detail.

Every measurement dated before 2026-08-27 is unsound, because the call could
read this repository until then. The case history has the detail.

`run.sh` proves that isolation on every run rather than trusting it. Before the
fan-out it asks the model to read back a token file outside the sandbox. The
token is never in the prompt, so an echo can only mean a real read. A leak
aborts the run, because a suite that cannot isolate reports nothing worth
having. An unexpected reply warns and continues, because it is no evidence
either way. The probe covers the tool channel only. `--safe-mode` closes the
CLAUDE.md, hooks, plugins, and settings channel, and nothing checks that.

### The second baseline: the prompt minus the paragraph

The stub is a cheap proxy, and it breaks in one direction that matters. A
paragraph sometimes exists to counteract the model's default. The stub then
agrees with the expected answer for its own reasons, and the ablation calls a
load-bearing case a no-op. The `consolidate-critic` case below is one instance.
The `garden` classification is another, and a broader one. Three of its four
tokens name actions any careful reviewer would also pick, so the vocabulary alone
carries the stub to the right answer.

The fix is the baseline the spike case already uses. Run the case against hone's
prose **minus the paragraph the case pins**, rather than against no prose at all.
The cheapest way to build that baseline is the prose as it stood before the
change under test, which `git show` prints. `--prompt-file` runs it without a
change to the working tree:

```bash
git show <commit-before>:skills/garden/SKILL.md > /tmp/garden-before.md
bash evals/run.sh garden --votes 3 --model opus --prompt-file /tmp/garden-before.md
```

For a paragraph with no such commit, copy the prompt, delete the paragraph
from the copy, and pass the copy.

A case earns its place by discriminating against **either** baseline, and the
list below records which one. A case that survives neither pins nothing, whatever
behaviour it describes.

## Run

```bash
bash evals/run.sh                       # every case, one vote, the critics' model
bash evals/run.sh plan-critic           # one target
bash evals/run.sh loop --model opus     # the run skill's instructions
bash evals/run.sh garden --model opus   # the garden skill's classification
bash evals/run.sh --votes 3             # plurality-of-3 per case (use pre-release)
bash evals/run.sh --votes 3 --holdout   # include the held-out cases (see below)
bash evals/run.sh --jobs 12             # up to 12 concurrent calls (default 8)
bash evals/run.sh --dry-run             # list cases + expected answers, no calls
bash evals/run.sh garden --ablate       # the discrimination check, not a suite run
```

Match the model to what actually runs in production, or the result means nothing.
The critics name the `opus` alias in their frontmatter, and a run without
`--model` reads it from there. A critic run on any other model prints a note,
because it answers an assignment question and gates no release. The `loop` and
`garden` targets use whatever model drives the session (`--model opus`). The
release gate of `garden` also runs on its floor, `--model sonnet`.

`--model` takes an alias or a full model ID. An alias floats: the provider can
re-point it, and two runs on `sonnet` a month apart may measure two models. So
the run resolves an alias once, from the envelope of its isolation probe, and
pins every call to the full ID. The header line prints that ID. A run that
cannot resolve its alias stops with exit 3.

## Driving the harness from a tool

Four flags let a script or an optimizer drive `run.sh`. `test/evals_test.sh`
proves their plumbing against a fake CLI, with no model calls.

```bash
bash evals/run.sh loop --model opus --cases land-proof-gate,review-command-refused
bash evals/run.sh plan-critic --prompt-file /tmp/candidate.md
bash evals/run.sh plan-critic --votes 3 --json /tmp/run.jsonl
bash evals/run.sh plan-critic --votes 3 --cache
```

The header of `run.sh` says what each flag does. Two things it does not say.
A `--json` record carries `target`, `case`, `vote`, `model`, `expected`,
`token`, `verdict`, `pass`, `cached`, `cost_usd`, and `reply`. `token` is that
vote's answer, `verdict` and `pass` repeat the case's plurality result on every
record, and `reply` is the full text the terminal discards. The vote number is
part of the cache key, so three votes stay three samples.

### Section ablation

The first use of these flags is to test a section of a prompt, not a case.
Copy the prompt, delete one section from the copy, and run the target on the
copy at `--votes 3`, on the floor model of the target. It is the run of the
second baseline, read in the other direction. There the run tests the case,
and here it tests the section.

Read the result under one rule. An unchanged suite is evidence only for a
section that a case aims at. If no case aims at the section, the run reports
nothing about it, and the section stays. Cut a section only when a case aims
at it and `bash evals/candidate.sh decide` accepts the cut. It reads the
`--json` files of both prompts, and
[`docs/development.md`](../docs/development.md) has its rules. The cut then
enters the repo as an ordinary prompt edit, through the release gate.

Two campaigns have run, and neither found a section to cut. The first was on
2026-09-17 over both critics, on claude-sonnet-5
([note](../docs/spikes/2026-09-17-first-section-ablation.md)). The second was
on 2026-09-18 on claude-opus-5
([note](../docs/spikes/2026-09-18-section-ablation-on-opus.md)). One rule came
out of the second. Delete the category word of a bullet from the *Output* list
together with the bullet, because the word alone carries the bullet on opus.

## Targets and cases

Each entry gives the expected answer, what the case pins, and the baseline
that it discriminates against. The measurements behind each entry, and the
drafts that died, are in
[`docs/spikes/2026-09-18-eval-case-history.md`](../docs/spikes/2026-09-18-eval-case-history.md).
Re-measure a case before you lean on its entry.

*`plan-critic`*, verdict `APPROVE` or `REJECT`, on claude-opus-5:

- `named-references`: APPROVE. It pins *Calibration*: the critic invents no
  objection. The opus stub approves too, so today it measures the sonnet
  floor only.
- `dep-refresh-no-red-test`: APPROVE. It pins *Calibration*, and no case
  pins the refresh bullet. The opus stub approves too.
- `handler-proof-for-endpoint`: APPROVE, a near miss. The opus stub
  approves too.
- `real-env-proof-described`: APPROVE, a near miss. The opus stub rejects
  3/3.
- `thin-proof-right-level`: APPROVE. The prompt minus *Calibration* rejects
  3/3 on opus. One vote in five still finds a fork in the brief.
- `nested-slug-open-plan`: REJECT with `slug-collision`. The stub approves,
  and so did the prompt before 0.53.1.
- `schema-silent-on-data`: REJECT with `disposable`. The stub rejects too
  and never says the word, so the substring is the whole case.
- `outcome-table-in-prose`: REJECT with `missing-artifact`. On opus the
  prompt minus the *Prose doing an artifact's job* bullet and its category
  word still rejects, and never says the word. So the substring is the
  whole case.
- `fork-closed-by-author`: REJECT with `ambiguity`. Its brief carries the
  caller's sketch, and the Plan settles a fork the sketch left open. The
  stub rejects too and never says the word, so the substring is the whole
  case. It pins the sketch in the brief, not any paragraph: the same brief
  with the sketch cut approves 2 of 3. No flag makes that baseline.
- `fork-settled-by-decision`: the twin above, with a Decision that settles the
  fork and a Plan that follows it. It approves on the full prompt, the stub,
  and the prompt minus the two Decision sentences, so it pins no prompt text.
  It stays the approving twin: a wording that rejects every fork fails it.
- `indexer-strips-only-copy`: REJECT with `contradiction`. Every claim the
  Plan makes is true, and the mechanism still destroys data for one of the
  inputs it runs over. From a real misjudgment.
- `invariant-overgeneralised`: REJECT with `contradiction`. Every citation
  checks out, and the rule drawn from them is false. From a real
  misjudgment.
- `tool-negative-from-config`: REJECT with `contradiction`. A negative claim
  about a third-party tool, backed only by a proxy signal in a config file.
  From a real misjudgment.
- `proof-probe-unnamed`: REJECT with the probe path. The Plan adds no probe
  under its slug. The stub and the prompt minus *A proof land cannot run*
  approve.
- `proof-probe-not-found`: the same, but the Plan extends another change's
  probe. The stub approves.
- `schema-split-column-holdout`: held out, a paraphrase of
  `schema-silent-on-data`.

The stub rejects the three cases from a real misjudgment and never says `contradiction`, so the
substring is the whole case in each.

The next cut of no-op cases decides the three that the opus stub approves.

*`consolidate-critic`*, verdict `CUTS` or `CLEAN`:

- `spike-note-may-age`: CLEAN. It no longer discriminates. It stays
  because a critic that always cuts must not score full marks. Read its
  tally first when a run degrades.
- `helper-single-caller`: CLEAN. On sonnet the prompt minus the
  single-caller bullet answered CUTS 2/3. On opus it answers CLEAN 3/3, so
  the case pins nothing on claude-opus-5.
- `spike-conclusion-only`: CUTS with `spike-drift`. The prompt minus the
  two sentences on a conclusion-only note answers CLEAN 3/3.
- `spike-verdict-only-holdout`: held out, a paraphrase of the case above.
- `same-claim-two-layers`: CLEAN. Two tests assert one proposition at two
  layers, so neither is redundant. The stub answers CLEAN too, and the
  prompt minus *Calibration* answers CUTS 3/3. From a real misjudgment.
- `ordered-deletion-not-in-diff`: CUTS with `leftover`. The Plan ordered a
  deletion that the diff does not show. The stub cuts too and never says the
  word, so the substring is the whole case. From a real misjudgment.
- `spike-note-contradicted-watch`: a watch case for the converse rule on
  spike notes (see *Watch cases*).

*`loop`*, the next action that `run` takes:

- `land-authority-gate`: RECORD, stub ASK.
- `land-proof-gate`: STOP, stub ASK.
- `land-proof-bootstrap`: STOP, stub RECORD, prior prose RECORD.
- `land-grant-beyond-plan`: STOP, stub ASK.
- `review-fanout-temptation`: NEST, stub ASK.
- `review-command-refused`: NEST. The isolated stub answers wrong.
- `review-envelope-denials`: PROCEED, stub HANDROLL. The prose before the
  rule answered NEST 3/3.
- `stop-report-one-action`: STOP with `recommend`. The token is never in
  doubt, so the substring is the whole case. Neither the stub nor the
  prose before the rule says the word.
- `worktree-claimed-single`: STOP. The isolated stub answers wrong.
- `plan-sequencing-constraint`: STOP, stub ASK.
- `consolidate-forecast-unprompted`: DISCARD, stub RECORD. The prose before
  the rule still answers DISCARD 2/3, so the case pins the rule at the
  margin.
- `missing-reference-holdout`: STOP, held out.

The stub halts on every land gate and says `ASK`. So `land-proof-gate` and
`land-grant-beyond-plan` pin the action word more than a judgment. That is
worth a case, because the loop dispatches on the word.

*`garden`*, what a pass does with one finding: `CUT`, `REPAIR`, `ESCALATE`,
or `NEXTPASS`. The stub answers most of these correctly, so the second
baseline is garden's prose before the repair, batching, and bounded-pass
rules.

- `moved-governs-path`: REPAIR with the new path. The prior prose answered
  ESCALATE 3/3.
- `src-comment-reference`: ESCALATE, stub REPAIR 3/3. *build* owns code.
- `midpass-review-finding`: NEXTPASS. The prior prose answered CUT 3/3. It
  pins the bound on a pass.
- `same-area-escalations`: ESCALATE with `auth-staleness`. The substring is
  the case: one Plan per area, not one per finding.
- `renamed-governs-holdout`: held out, a paraphrase of `moved-governs-path`.

## Known gaps

- *`consolidate-critic`*: three visible cases, and most of the critic is
  ungated. The stub cuts a leftover, a Decision that restates code, and a
  redundant test without help. So a CUTS case pins a category word at best.
- *`plan-critic`*: a REJECT case pins what the critic says when it rejects,
  never whether it rejects. The stub rejects every flawed Plan tried so
  far. The cases that discriminate are near misses, and only where the stub
  invents an objection.
- *`garden`*: no case pins the rule against a prompt-layer cut, because the
  model is already reluctant to delete instructions. The landing mechanics
  stay ungated, as the loop's do.

Four rules from the drafts that died. The case history has the tallies.

- Bury the thing under test in the brief, and ask only for the next action.
  A brief that names it measures agreement.
- Leave the critic exactly one thing to cut in a CUTS case.
- Pick a required substring that the prose mandates, not one the topic
  suggests. The scoring pools the votes, so one stray word passes.
- Add no second cut target to a `consolidate-critic` brief. It raises what
  the critic cuts everywhere.

## Held-out cases

`run.sh` skips case dirs named `*-holdout` unless you pass `--holdout`, and they
are the check against tuning to the suite. Trimming prose and re-running
optimizes against the visible cases. Prose can then pass the very briefs you
trimmed it against, while the behavior can still be gone in any paraphrase. So:
never read a holdout brief or edit prose with one in view. Run `--holdout` once,
as the last check before a release. A holdout failure after a green main suite is
the overfitting signal. Fix the prose, never the holdout case.

## Watch cases

A case dir named `*-watch` is in no suite run, with or without `--holdout`.
It runs only when `--cases` names it. A watch case is a brief on which a
paragraph still moves a tally and flips no plurality, so it cannot gate
anything today. It exists for the expiry check of a new model. Run it at
five votes against the full prompt and against the prompt minus the
paragraph. Then compare the tallies.

```bash
bash evals/run.sh consolidate-critic --votes 5 --cases spike-note-contradicted-watch
bash evals/run.sh consolidate-critic --votes 5 --cases spike-note-contradicted-watch \
    --prompt-file /tmp/critic-minus-converse-rule.md
```

## How a case is scored

Each case is `evals/<target>/<case>/`. It holds a self-contained `brief.md` and
an `expected` file. The first line of `expected` is the token. Each further line
is a substring the reply must mention. The check ignores case.

The runner puts the prose under test in the system slot: the agent body for a
critic, and `skills/run/SKILL.md` for the loop. The brief goes in the user turn,
and the runner calls `claude -p` headless with `--output-format json`. It reads
the reply from that envelope, and an error envelope counts as no answer. It
takes the last token in the reply as that run's answer. Every target's instruction demands an exact final line
(`ACTION:`/`VERDICT:`), so the token is the stated answer. It is not one the
model happened to name last while reasoning.

The runner scores votes by plurality. `tokens_for` in `run.sh` lists each
target's tokens most-conservative-first. A tie therefore breaks toward the
conservative token, so a split critic rejects and a split loop stops. The
required substrings must appear in a vote that carried the verdict.

A case where every vote failed to answer is a loud FAIL, never a pass. A dead
harness therefore cannot turn the suite green, and it cannot fall through to
whichever token the case expected. A target with no cases fails for the same reason.

Each result line carries its vote count. An example: `ok  land-proof-gate → STOP
(3/3)`. A non-unanimous case shows its split instead, and a pass at 2/3 is still
a pass. But a case that moves from unanimous to split across prompt edits is
degrading. The tally is where that shows, before it flips.

Every `case × vote` call is independent and fans out concurrently, capped at
`--jobs`. `--votes` exists because these are borderline judgments with real
sampling variance. Raising `--jobs` is faster but can hit API concurrency limits
and error a call, which scores as no answer.

## The noise floor

A claim that a prose cut changed nothing needs a number for how much the
suite moves when nothing changed. The measurement is three identical
full-suite passes at `--votes 3` on one commit.

| Date | Models | Votes | Flipped pluralities | Dissenting votes |
| --- | --- | --- | --- | --- |
| 2026-09-01 | critics sonnet, loop and garden opus | 153 | 0 of 51 | 1 |
| 2026-09-17 | critics claude-sonnet-5, the rest claude-opus-5 | 171 | 0 of 57 | 5 |
| 2026-09-18 | every target claude-opus-5 | 216 | 0 of 72 | 1 |
| 2026-09-25 | every target claude-opus-5-5 | 297 | 0 of 99 | 0 |

So a flipped plurality after a prompt edit is signal, and a tally that
moves by one vote is noise. A pass cost about 3.70 dollars on 2026-09-25.
Measure the floor again before an ablation campaign and on every new
model. The run header prints the full model ID, so compare it with the
last row.

## Extending

Add a case whenever a critic misjudges a real change, or when the loop takes a
wrong turn. Capture the brief that fooled it, and the answer it should have
reached. Then ablate it before you keep it, with `run.sh` itself and never a
hand-rolled check. The scoring pools every vote that carried the verdict. So a
required substring that is merely on-topic can pass on one lucky vote, and a
per-vote check misses that. `schema-silent-on-data` had one such miss. A
case that the stub answers correctly is not a regression net, however real
the misjudgment that prompted it.

A case the shipped prompt fails goes to `evals/optimize/cases/` instead of
into a suite. Its README says why.
