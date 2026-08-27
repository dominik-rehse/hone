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

Before 2026-08-27 it ran the call from the repository root with tools on. A stub
run then quoted a paragraph of `agents/consolidate-critic.md` back verbatim,
including a category label that existed only in an uncommitted edit.

The contamination has **no single direction**, and that is what makes it
expensive. Repo context sometimes carried the stub toward hone's answer, which
reads as a no-op and cuts a load-bearing case. It sometimes carried the stub
away from it, which reads as discrimination a clean stub does not show. Both
happened on 2026-08-27, in the same target, on the same day.
`consolidate-proof-forecast` is the second kind: the contaminated stub answered
RECORD, the isolated stub answers DISCARD, and the case pins nothing.

So every measurement in this file dated before 2026-08-27 is unsound in both
directions. That covers the 44-case cut of 2026-08-18 and the recorded stub
answer beside every surviving case. Re-measure a case before you lean on its
number.

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
change under test, which `git show` prints:

```bash
git show <commit-before>:skills/garden/SKILL.md > skills/garden/SKILL.md
bash evals/run.sh garden --votes 3 --model opus
git checkout skills/garden/SKILL.md
```

A case earns its place by discriminating against **either** baseline, and the
list below records which one. A case that survives neither pins nothing, whatever
behaviour it describes.

The 2026-08-18 measurement used sonnet for the critics and opus for the loop, and
it found 44 no-ops among the 52 cases then present. The cut removed them. Eight
cases remained, two land-gate cases joined them on 2026-08-19, and one
sequencing case joined on 2026-08-20. The list
below carries each case with the stub's answer that justified keeping it.

## Run

```bash
bash evals/run.sh                       # every case, one vote, model=sonnet
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
The critics carry `model: sonnet` in their frontmatter. The `loop` and `garden`
targets use whatever model drives the session (`--model opus`).

## Targets and cases

Each entry gives the expected answer, then what the stub answered without hone's
prose. The gap between the two is what the case pins.

Each entry below carries the stub answer measured on the date it names, on the
contaminated harness. A re-measurement of all 15 surviving cases on 2026-08-27,
isolated, three votes, moved three numbers and left the rest standing:

- `dep-refresh-no-red-test`: the isolated stub APPROVES 3/3, so it no longer
  discriminates against the neutral stub at all. It survives on the second
  baseline instead. The plan-critic prompt minus its *Dependency and toolchain
  refreshes* bullet rejects the Plan 2/3.
- `named-references`: the isolated stub rejects 2/3 rather than 3/3. It still
  discriminates.
- `loop`: the isolated stub now misses **all 8** remaining cases, against 6 of 9
  before. Every one of them discriminates harder than its entry claims.

`garden` and `spike-note-may-age` measured the same either way.

*`plan-critic`*, verdict `APPROVE`/`REJECT`:

- `named-references`: APPROVE, stub REJECT 3/3. The stub clears every rejection
  category in turn. It calls the one loose end "not reject-worthy on its own",
  then rejects anyway. This case pins the calibration that tells the critic not
  to invent objections.
- `dep-refresh-no-red-test`: APPROVE, stub REJECT 2/3. A toolchain refresh has no
  red test to write first. Without the rule that says so, the missing test reads
  as a placeholder.

*`consolidate-critic`*, the verdict on what a change left behind:

- `spike-note-may-age`: CLEAN, stub CLEAN 3/3. The stub agrees, so by the rule
  above this case is a no-op that should go. It stays because the
  neutral stub is the wrong baseline here. What it pins is not judgment the
  model lacks. It is a guard against hone's *own* deletion bias, which the stub
  does not carry. The real baseline is the critic prompt with the spike
  paragraph removed. Measured against it, the critic cuts the aged spike note
  2/3, where the full prompt leaves it 3/3. The paragraph is load-bearing, and this case
  is what pins it.

  Read that as a limit of the ablation rule, not an exception to it. The rule
  asks whether hone's prose changes the answer, and the stub is a cheap proxy
  for that. Where a paragraph exists to counteract another paragraph, the
  proxy breaks, and the ablation has to run against the prompt minus the
  paragraph instead.

*`loop`*, the next action `run` takes:

- `land-authority-gate`: RECORD, stub ASK 3/3 (measured 2026-08-18, when the
  case expected STOP).
- `land-proof-gate`: STOP, stub ASK 3/3.
- `land-proof-bootstrap`: RECORD, stub HANDROLL 3/3 (measured 2026-08-19).
- `land-grant-beyond-plan`: STOP, stub ASK 2/3, STOP 1/3 (measured 2026-08-19).
- `review-fanout-temptation`: NEST, stub ASK 3/3.
- `review-command-refused`: NEST, stub NEST 2/3, HANDROLL 1/3.
- `worktree-claimed-single`: STOP, stub STOP 2/3, SKIP 1/3.
- `plan-sequencing-constraint`: STOP, stub ASK 2/3, STOP 1/3 (measured
  2026-08-20). The Plan orders this change after another one, and the diff
  falsifies the reason the Plan gave. The stub hands the human a menu that
  includes editing the Plan. hone treats the Plan's constraint as a check, so
  the run stops.
- `missing-reference-holdout`: STOP, stub ASK 2/3, STOP 1/3.

*`garden`*, what a maintenance pass does with one scan finding. Tokens are
`CUT`, `REPAIR`, `ESCALATE`, and `NEXTPASS`. Every case here was measured against
both baselines on 2026-08-25, opus, three votes. The stub answered seven of the
eight candidate cases correctly. So the second baseline is what most of these
pin. That baseline is garden's prose before the repair, the batching, and the
bounded-pass rules landed.
Three cases that survived neither baseline were cut the same day:
`claim-moved-too`, `two-candidate-targets`, and `prompt-gotcha-no-evals`.

- `moved-governs-path`: REPAIR. Stub REPAIR 3/3, so it is a no-op by the cheap
  proxy. The prior prose answered ESCALATE 3/3, and that is what it pins. A
  `Governs:` path whose code merely moved used to cost a whole `plan → run`
  cycle. The required substring is the new path, so a vague "repoint it" does
  not pass.
- `src-comment-reference`: ESCALATE. Stub REPAIR 3/3. This is the only case that
  discriminates against the neutral stub, and the clearest one. Fixing a stale
  path in a `src/` comment is what any reviewer would do. It is also exactly
  what garden may not do, because *build* owns code.
- `midpass-review-finding`: NEXTPASS. Stub NEXTPASS 3/3, prior prose **CUT
  3/3**. It pins the bound on a pass. The finding is real, it is garden's own
  scan class, and the pass still refuses it because its own scan did not report
  it. This is the case that stands between a maintenance pass and an open-ended
  one.
- `same-area-escalations`: ESCALATE, and the token is not what it pins. Both
  baselines answer ESCALATE. The prior prose omits the required substring
  `auth-staleness`, because it proposes a Plan per finding instead of one per
  area. The substring is the whole case.
- `renamed-governs-holdout`: REPAIR, held out. It paraphrases
  `moved-governs-path` with different content, and it measured the same way:
  stub REPAIR 3/3, prior prose ESCALATE 3/3.

Read the loop gap precisely. The stub halts on every land gate and picks `ASK`.
`land-proof-gate` and `land-grant-beyond-plan` therefore pin hone's action
vocabulary more than judgment the model lacks, since halting was the right
instinct and only the word was wrong. That is still worth pinning, because the
loop dispatches on the word. The other two are stronger. On
`land-authority-gate` and `land-proof-bootstrap` the stub halts where hone
discharges the gate and lands, so the case pins the action itself, as the
plan-critic pair do.

## Known gaps

The cut left two gaps, and the `garden` target opened a third. All three are
deliberate, and the suite barely covers any of them.

*`consolidate-critic` has one case, and most of the target stays ungated.* All
13 original cases were no-ops. A model with no hone prose reached the
same verdict on every one. `spike-note-may-age` (2026-08-19) is the first
replacement, and it pins one paragraph rather than the critic as a whole.
`run.sh` fails an empty target loudly rather than reporting an empty green.
The remaining gap therefore stays visible. Closing it needs briefs harder than
the model's default judgment, not the old ones back.

On 2026-08-27 a change tried to add a seventh target to this critic,
`decision-forecasts`. It cuts a Decision sentence that predicts what a proof
run will show. Neither the case nor the target survived measurement, and the
attempt is worth recording.

The case died in the ablation. Both baselines cut the forecasting paragraph
3/3. The neutral stub cut it on the merits, and the critic prose from before
the rule cut it as a `leftover` that duplicates the open question. A second,
harder brief removed the word-for-word duplication, and both baselines still
cut it.

The target then failed the suite. Three shapes went through the fixed harness:
a gated bullet, a short bullet, and one sentence folded into
`decision-restates-code`. Each flipped `spike-note-may-age` from `CLEAN` 5/5
to `CUTS`, at 4/5, 3/5, and 5/5. What the critic proposed to cut was never the
spike note, whose guard held every time. It was the Decision's opening
sentence, on a `decision-restates-code` reading that stands up by itself. So
another cut target does not sharpen this critic. It raises what the critic
cuts anywhere in the brief, and the marginal call goes with it.

A `loop` case for the same rule died the same day, and it died for a reason
worth separating from the two above. Asked point-blank what to do with a
drafted Decision paragraph that forecasts, every baseline answers DISCARD.
The isolated stub answered it 2/3, and the loop prose from before the rule
answered it 3/3. The question carries its own answer. The real failure had nobody asking it. An
agent at consolidate wrote the forecast unprompted. The Decision wanted
present-tense prose, and no measurement existed yet. A brief that hands
the model the suspect paragraph cannot reproduce that. So the rule ships in
`skills/run/SKILL.md` unpinned, and the gap is the brief, not the rule.

*`plan-critic` has no REJECT case.* Both survivors expect APPROVE, so an
always-APPROVE critic scores 2/2. The suite can no longer see a critic that has
gone permissive. The stub rejected every REJECT case too, which is why the cut
took them all. The same finding from the other side: the rejection categories need no
pinning, and the restraint does.

*The prompt layer stays unpinned, in `garden` as everywhere else.* garden refuses
to cut a `CLAUDE.md` paragraph in a repo with no eval suite. That is one of its
sharper rules. The case written for it (`prompt-gotcha-no-evals`, 2026-08-25)
died in the ablation. Both baselines answered ESCALATE 3/3, because the model is
already reluctant to delete instructions someone handed it. The rule may still be
load-bearing under a model that is less reluctant. No brief written so far shows
it. The same measurement retired `claim-moved-too` and `two-candidate-targets`.
Both described repair conditions that a careful reader applies unprompted.
What `garden` pins is therefore the four cases above, not the skill as a whole.
Its landing mechanics (the `Cut:` and `Repair:` lines, the progress line, the
ledger) stay ungated, as the loop's do.

## Held-out cases

`run.sh` skips case dirs named `*-holdout` unless you pass `--holdout`, and they
are the check against tuning to the suite. Trimming prose and re-running
optimizes against the visible cases. Prose can then pass the very briefs you
trimmed it against, while the behavior can still be gone in any paraphrase. So:
never read a holdout brief or edit prose with one in view. Run `--holdout` once,
as the last check before a release. A holdout failure after a green main suite is
the overfitting signal. Fix the prose, never the holdout case.

## How a case is scored

Each case is `evals/<target>/<case>/`. It holds a self-contained `brief.md` and
an `expected` file. The first line of `expected` is the token. Each further line
is a substring the reply must mention. The check ignores case.

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

## Extending

Add a case whenever a critic misjudges a real change, or when the loop takes a
wrong turn. Capture the brief that fooled it, and the answer it should have
reached. Then ablate it before you keep it. A case that the stub answers
correctly is not a regression net, however real the misjudgment that prompted it.
