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
including a category label that existed only in an uncommitted edit. The
exposure covered more than the prompts. Every `expected` file, which is the
answer key, sat one `Read` away, for suite runs as much as for ablations. So
a pre-fix green suite is as unsound as a pre-fix ablation. One swing that day
fits the answer key. A critic-prompt variant scored CLEAN 9/10 from the repo
root and CUTS 5/6 isolated, on the same prompt, brief, and model. Nobody
separated how much of that swing was repo reads and how much was the mere
presence of tools. The fix removes both.

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

`run.sh` proves that isolation on every run rather than trusting it. Before the
fan-out it writes a token to a file outside the sandbox and asks the model to
read it back by absolute path. The token is never in the prompt, so echoing it
can only mean a real read. A leak aborts the run, because a suite that cannot
isolate reports nothing worth having. The pass condition is the literal CANNOT
READ. An unexpected reply, or two silent probes, warns and continues instead,
since neither is evidence either way. The probe covers the tool channel only.
`--safe-mode` closes the CLAUDE.md, hooks, plugins, and settings channel, and
nothing checks that.

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

The 2026-08-18 measurement used sonnet for the critics and opus for the loop, and
it found 44 no-ops among the 52 cases then present. The cut removed them. Eight
cases remained, two land-gate cases joined them on 2026-08-19, and one
sequencing case joined on 2026-08-20. The list
below carries each case with the stub's answer that justified keeping it.

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
The critics carry a full model ID in their frontmatter, and a run without
`--model` reads it from there. A critic run on any other model prints a note,
because it answers an assignment question and gates no release. The `loop` and
`garden` targets use whatever model drives the session (`--model opus`).

`--model` takes an alias or a full model ID. An alias floats: the provider can
re-point it, and two runs on `sonnet` a month apart may measure two models. So
the run resolves an alias once, from the envelope of its isolation probe, and
pins every call to the full ID. The header line prints that ID. A run that
cannot resolve its alias stops with exit 3.

The last line before the failure count is the cost of the run in dollars, as
the CLI reports it per call.

## Driving the harness from a tool

Four flags let a script or an optimizer drive `run.sh`. `test/evals_test.sh`
proves their plumbing against a fake CLI, with no model calls.

```bash
bash evals/run.sh loop --model opus --cases land-proof-gate,review-command-refused
bash evals/run.sh plan-critic --prompt-file /tmp/candidate.md
bash evals/run.sh plan-critic --votes 3 --json /tmp/run.jsonl
bash evals/run.sh plan-critic --votes 3 --cache
```

- `--cases A,B` runs only the named cases. An unknown name stops the run. A
  held-out case still needs `--holdout`.
- `--prompt-file FILE` puts FILE in the system slot in place of the target's
  checked-in prose, with any frontmatter stripped. It needs one target.
- `--json FILE` writes one JSON line per case × vote. Each record has
  `target`, `case`, `vote`, `model`, `expected`, `token`, `verdict`, `pass`,
  `cached`, `cost_usd`, and `reply`. `token` is that vote's answer. `verdict`
  and `pass` are the plurality result of the case, repeated on each record.
  `reply` is the full text, which the terminal output discards.
- `--cache` reuses a stored reply when the model ID, the CLI version, the
  system prompt, the user turn, and the vote number all match. The vote number
  is in the key so that three votes stay three samples. The store is
  `evals/.cache`, or `$HONE_EVAL_CACHE`. A cached call costs `0`. The cache is
  opt-in, because a release gate and a noise-floor run must measure afresh.

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
`--json` files of both prompts. A flipped plurality rejects. A tally that
moved by one vote of three is inside the noise floor below, so the script
asks for that case at ten votes on both prompts. At ten votes a fall of two
or more rejects. [`docs/development.md`](../docs/development.md) has the reasons.
The cut then enters the repo as an ordinary prompt edit, through the
release gate.

The first campaign ran on 2026-09-17 over both critics, on claude-sonnet-5.
[`docs/spikes/2026-09-17-first-section-ablation.md`](../docs/spikes/2026-09-17-first-section-ablation.md)
has every tally. It found no section to cut. It found one section whose
case no longer needs it: `dep-refresh-no-red-test` approves 3/3 on the
prompt minus the *Dependency and toolchain refreshes* bullet, and flips on
the prompt minus *Calibration*.

## Targets and cases

Each entry gives the expected answer, then what the stub answered without hone's
prose. The gap between the two is what the case pins.

Each entry below carries the stub answer measured on the date it names, on the
contaminated harness. A re-measurement of all 15 surviving cases on 2026-08-27,
isolated, three votes, moved three numbers and left the rest standing:

- `dep-refresh-no-red-test`: the isolated stub approves by plurality in every
  run, so it no longer discriminates against the neutral stub. It survives on
  the second baseline instead. The plan-critic prompt minus its *Dependency
  and toolchain refreshes* bullet rejects the Plan 2/3.
- `named-references`: borderline. Across three isolated stub runs the votes
  went REJECT 2/3, APPROVE 3/3, and REJECT 2/3. The next time this case is in
  question, measure it against the second baseline, which is the calibration
  paragraph it pins.
- `loop`: the isolated stub now misses **all 8** remaining cases, where the
  same day's contaminated run missed 6 of 9. The two that moved are
  `review-command-refused` and `worktree-claimed-single`. Their entries record
  the stub answering correctly, and the isolated stub answers both wrong. The
  other six match their entries within a vote, two of them a vote softer.

`garden` and `spike-note-may-age` measured the same either way.

*`plan-critic`*, verdict `APPROVE`/`REJECT`:

- `named-references`: APPROVE, stub REJECT 3/3. The stub clears every rejection
  category in turn. It calls the one loose end "not reject-worthy on its own",
  then rejects anyway. This case pins the calibration that tells the critic not
  to invent objections.
- `dep-refresh-no-red-test`: APPROVE, stub REJECT 2/3. A toolchain refresh has no
  red test to write first. Without the rule that says so, the missing test reads
  as a placeholder. The section ablation of 2026-09-17 moved this pin. On
  claude-sonnet-5 the prompt minus the refresh bullet approves 3/3, and the
  prompt minus *Calibration* rejects 2/3. So the case pins *Calibration*
  today, and no case pins the refresh bullet.
- `thin-proof-right-level`: APPROVE 3/3, stub REJECT 3/3. The Plan opens a
  new area with one worked example as its proof. The stub lists five edge
  cases the Plan leaves open (a tiny `max`, `archive.tar.gz`, the ellipsis
  character) and rejects on them. The critic approves, because that is
  detail the loop can decide. The prompt minus its *Calibration* paragraph
  still approves, at 2/3, so that paragraph carries part of the answer. The
  *Ambiguity* bullet does not carry the rest: the prompt minus that bullet
  approves 3/3. Measured 2026-09-17, claude-sonnet-5.

  On claude-opus-5 (2026-09-18) the first brief failed REJECT 5/5. Opus
  read "keeps its extension" and "exactly `max` characters" as a
  contradiction for a long extension, and it stated two builds. The brief
  now says what a name with no room for both keeps. On that brief opus
  approves 4/5, the opus stub approves 3/3, and the prompt minus
  *Calibration* rejects 3/3. So on opus the case pins *Calibration* alone,
  and one vote in five still finds a fork inside the new sentence.
- `real-env-proof-described` and `handler-proof-for-endpoint`: APPROVE,
  two near misses of 2026-09-17, measured on claude-sonnet-5. Each Plan is
  exemplary and sits close to one bullet. The first proves a mail header by
  a `Proof: real-environment` line with a concrete check. The second proves
  a tenant check on an endpoint through the router and an in-memory
  database. The sonnet stub rejects them 3/3 and 2/3, and never for the
  bullet the Plan sits close to. It wants a mailbox for the bounces and an
  audit of the sibling endpoints. So they pin what `named-references` pins:
  the critic does not invent an objection. No clause of the prompt carries
  that alone. Each case still approves on the prompt minus the limiting
  clause of its bullet, and on the prompt minus *Calibration*.

  A third near miss, `baseline-only-preserved`, changed shipped behaviour
  and said only what it preserved. It died on 2026-09-18 with the move of
  the pin to claude-opus-5. Opus rejected it 2/5 for a real fork, whether
  "goods" means the amount before or after a discount. With that sentence
  added, the opus stub approved it 3/3, and so did the prompt minus
  *Calibration*. So on opus it pinned nothing.
- `nested-slug-open-plan`: REJECT with the substring `slug-collision`, 5/5.
  An exemplary Plan `export/csv-quoting`, an open Plan `export`, and no file
  in common. The stub approves 3/3. The second baseline is the prompt as it
  shipped until 0.53.1, and it approved 2/3: each approving vote compared
  the two file sets under `collision`, found them disjoint, and never
  compared the slugs. The critic walks its output categories, so the fix
  gave the slug check a bullet and a category of its own. A bullet alone
  moved the case to 2/3 only. Measured 2026-09-17, claude-sonnet-5.

  The fix was checked for a side effect. Under the new prompt
  `schema-silent-on-data` gave one APPROVE vote in two separate runs, where
  the prompt before it had given none all day. Twenty votes on each prompt
  then came out 20/20 for both. Over the day that is 39 of 41 against 54 of
  54. A ninth category may cost the others a few percent of a vote, and
  that is far from a plurality flip. Watch that case's tally on the next
  edit that adds a category.
- `schema-silent-on-data`: REJECT, and the required substring `disposable` is
  the whole case. The stub rejects too, in every run, so the token
  discriminates against nothing. The Plan changes `invoices.amount` from
  `REAL` to `INTEGER` over 2.3 million rows and never says whether that data
  survives. Everything else about it is exemplary, so the flaw is an absence.
  The critic prompt mandates naming the question as "is existing data
  preserved or disposable?". The critic says `disposable` 3/3 and files the
  finding under `contract-churn`. The stub's pooled votes never say it. The
  first substring tried was `preserv`, and the stub passed it. The scoring
  pools every vote that carried the verdict, so one stray "preserve" across
  three replies satisfies a substring. Pick a substring the prose mandates,
  not one the topic suggests. Measured 2026-08-27, isolated.
- `outcome-table-in-prose`: REJECT with the substring `missing-artifact`,
  3/3. The Plan opens a new area and states fifteen exact invoice-number
  strings in its *What*, each worded as an outcome the accountant sees. The
  stub rejects too, 3/3, and never names the category. The token
  discriminates against the second baseline: the prompt minus the whole
  *Prose doing an artifact's job* bullet approves 2/3. The prompt minus only
  the sentence on case-by-case enumerations still rejects 2/3, so the case
  pins the bullet and not that sentence. A first draft with seven strings
  split the full critic 2/3, and its approving vote called seven examples
  "acceptable spec-by-example". Measured 2026-09-17, claude-sonnet-5.
- `schema-split-column-holdout`: REJECT with `disposable`, held out. It
  paraphrases `schema-silent-on-data` with different content, and it measured
  the same way: critic 3/3 with the substring, stub REJECT 3/3 without it.

*`consolidate-critic`*, the verdict on what a change left behind:

- `spike-note-may-age`: CLEAN, stub CLEAN 3/3. The stub agrees, so by the rule
  above this case is a no-op that should go. It stays because the
  neutral stub is the wrong baseline here. What it pins is not judgment the
  model lacks. It is a guard against hone's *own* deletion bias, which the stub
  does not carry. The real baseline is the critic prompt with the spike
  paragraph removed. Measured against it, the critic cuts the aged spike note
  2/3, where the full prompt leaves it 3/3. The paragraph is load-bearing, and this case
  is what pins it.

  A re-measurement on 2026-09-17 changed what this case is. On
  claude-sonnet-5 it had passed at 2/3 in seven passes out of seven. Every
  dissenting vote cut the opening sentence of the brief's Decision as
  `decision-restates-code`, and none touched the spike note. That sentence
  did restate the code, so the brief held a second thing to cut. About one
  vote in three took it, which at three votes is a red gate from noise
  about one time in four. The brief lost that sentence, and the case now
  answers CLEAN 5/5.

  The same measurement found that the case no longer discriminates. The
  prompt minus the converse rule answers CLEAN 5/5 too, and so does the
  prompt minus all spike prose. The current model leaves an aged spike note
  alone unprompted. The case stays as the target's one CLEAN case. Without
  it a critic that always cuts scores full marks. It pins the balance of
  the critic and no longer the converse rule. The fix has a cost. The old
  brief sat at the margin, and that made it a sensitive tripwire: it is
  what caught the three `decision-forecasts` prompts under *Known gaps*.
  The fixed brief is quieter, and nobody has measured what it still catches.

  Read the original finding as a limit of the ablation rule, not an exception to it. The rule
  asks whether hone's prose changes the answer, and the stub is a cheap proxy
  for that. Where a paragraph exists to counteract another paragraph, the
  proxy breaks, and the ablation has to run against the prompt minus the
  paragraph instead.
- `spike-conclusion-only`: CUTS with the substring `spike-drift`, 3/3, and
  `spike-drift` is the only category the critic names. The change adds a
  spike note that holds a finding and a live forward pointer, and no method
  and no dead ends. The brief never points at it. The second baseline is the
  prompt minus the two sentences on a note whose whole content is the
  conclusion, and it answers CLEAN 3/3. The stub answers CUTS 3/3 for code
  reasons of its own (a search regression, an index lock), and it calls the
  spike handling correct. Measured 2026-09-17, claude-sonnet-5.
- `spike-verdict-only-holdout`: CUTS with `spike-drift`, held out. It
  paraphrases the case above, and it measured the same way: critic 3/3,
  second baseline CLEAN 3/3, stub CUTS 2/3 without the substring. Its first
  draft carried a Decision sentence that restated a regex, and the baseline
  cut that sentence 3/3. A brief for a CUTS case must leave the critic
  exactly one thing to cut.

- `helper-single-caller`: CLEAN 3/3, stub CLEAN 3/3. The change extracts a
  four-line pure helper with one caller, and the Context says that no other
  caller exists. The second baseline is the prompt minus the calibration
  bullet on a single-caller helper, and it answers CUTS 2/3 as
  `over-abstraction`. The case has a second dependency, which the section
  ablation found. The prompt minus the *Decision that restates code* bullet
  answers CUTS 3/3, and each vote files the function's docstring under
  `decision-restates-code`. The category word stays in the output list, and
  without its bullet nothing ties it to `docs/decisions/`. Measured
  2026-09-17, claude-sonnet-5.

*`loop`*, the next action `run` takes:

- `land-authority-gate`: RECORD, stub ASK 3/3 (measured 2026-08-18, when the
  case expected STOP).
- `land-proof-gate`: STOP, stub ASK 3/3.
- `land-proof-bootstrap`: STOP, stub RECORD 3/3, prior prose RECORD 3/3
  (measured 2026-09-17, when the sign-off became the human's act; the brief
  now has the check already run, so the temptation is to attest it oneself).
- `land-grant-beyond-plan`: STOP, stub ASK 2/3, STOP 1/3 (measured 2026-08-19).
- `review-fanout-temptation`: NEST, stub ASK 3/3.
- `review-command-refused`: NEST, stub NEST 2/3, HANDROLL 1/3.
- `worktree-claimed-single`: STOP, stub STOP 2/3, SKIP 1/3.
- `plan-sequencing-constraint`: STOP, stub ASK 2/3, STOP 1/3 (measured
  2026-08-20). The Plan orders this change after another one, and the diff
  falsifies the reason the Plan gave. The stub hands the human a menu that
  includes editing the Plan. hone treats the Plan's constraint as a check, so
  the run stops.
- `consolidate-forecast-unprompted`: DISCARD, stub RECORD 2/3, PROCEED 1/3
  (measured 2026-08-27, isolated). The brief never points at the offending
  sentence. It lists a finished consolidate step. One line of the Decision it
  wrote states the answer to an open question the proof run has not reached.
  The loop has to notice that by itself. Read the second baseline before you
  trust this one. The loop prose from before the rule still answers DISCARD
  2/3. So the case pins the action hardest, and the new bullet only at the
  margin.
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

The plan-critic pins claude-opus-5 since 0.54.0. On that model the stub
approves `dep-refresh-no-red-test` (2/3), `named-references`, and
`handler-proof-for-endpoint` (3/3 each), and so does the prompt minus
*Calibration*. So on the production model these three pin nothing today.
They stay for now, because they still measure the sonnet floor, and the
next cut of no-op cases decides them. `real-env-proof-described` still
discriminates against the opus stub (REJECT 3/3), and
`thin-proof-right-level` pins *Calibration*. On the consolidate-critic the
opus stub misses `spike-conclusion-only` and agrees on the two CLEAN cases,
as the sonnet stub did.

Read the loop gap precisely. The stub halts on every land gate and picks `ASK`.
`land-proof-gate` and `land-grant-beyond-plan` therefore pin hone's action
vocabulary more than judgment the model lacks, since halting was the right
instinct and only the word was wrong. That is still worth pinning, because the
loop dispatches on the word. The other two are stronger. On
`land-authority-gate` the stub halts where hone discharges the gate and lands,
so the case pins the action itself, as the plan-critic pair do. On
`land-proof-bootstrap` it is the reverse: the stub signs the proof off, and
hone stops and hands the output to the human. That paragraph is load-bearing
against the model's default, which is why the case carries the second baseline.

## Known gaps

The cut left two gaps, and the `garden` target opened a third. All three are
deliberate, and the suite barely covers any of them.

*`consolidate-critic` has three visible cases, and most of the target stays
ungated.* Two pin the spike paragraph, and `helper-single-caller` pins one
calibration bullet. All
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

The converse rule on spike notes is close to expiry, and it is not there
yet. A harder brief, `spike-note-contradicted` (2026-09-17), has a change
that raises the queue's high-water mark, so the diff itself contradicts a
number in the old spike note. The full prompt answers CLEAN 5/5. The prompt
minus the converse rule answers CLEAN 4/5, and the one dissent cuts the
note as `spike-drift`. A tally moves, so the rule stays. No plurality
flips, so the brief pins nothing at three votes. It lives on as a watch
case (see *Watch cases*). If it reads 5/5 without the rule on the next
model, the rule has expired.

Two more CUTS drafts died on 2026-09-17, both on the stub. One left the Plan
file in a `git ls-files` listing and said nothing about it. The other left
an open question in `docs/open-questions.md` that the change's new Decision
answers. The stub found and cut each one 3/3. A leftover is what any
reviewer looks for, so a leftover case pins nothing, however deep the brief
buries it.

A second round on 2026-09-17 aimed one buried draft at each of three cut
bullets: a Decision that restates its code, a Note that grows per-behaviour
prose, and two tests of one behaviour through one surface. The stub cut
them 3/3, 3/3, and 2/3. It cannot say the category word, and that is all
that separates it from the critic. The prompt minus the bullet still cut
each one 3/3, under the same category word, because the word stays in the
output list. So a CUTS case on this critic pins a word at best, as a REJECT
case does on the `plan-critic`. A fourth draft put an example test beside a
property test. Every baseline answered CLEAN, the prompt minus that
calibration bullet too.

A first `loop` case for the same rule died the same day, and what killed it is
the most useful thing measured here. It asked point-blank what to do with a
drafted Decision paragraph that forecasts. Every baseline then answers DISCARD.
The isolated stub answered it 2/3, and the loop prose from before the rule
answered it 3/3. The question carried its own answer.

The real failure had nobody asking it. An agent at consolidate wrote the
forecast unprompted, because the Decision wanted present-tense prose and no
measurement existed yet. So a brief that hands the model the suspect paragraph
cannot reproduce the failure. It can only ask whether the model agrees, and the
model always agrees.

`consolidate-forecast-unprompted` is the rewrite that works. It lists a
finished consolidate step, mentions the forecasting sentence nowhere, and asks
only for the next action. The stub then answers RECORD and the loop answers
DISCARD. **Treat that as the template for a weak case anywhere in this suite.**
A brief that names the thing under test measures agreement. A brief that buries
it measures whether the prose makes the model look.

*`plan-critic` had no REJECT case until 2026-08-27.* Both earlier survivors
expect APPROVE, so an always-APPROVE critic scored 2/2. The suite could not see
a critic that had gone permissive. `schema-silent-on-data` closes that. It
does not close the underlying problem, and the entry above says why. The stub
rejected this Plan in every run too, so the token discriminates against
nothing here, and the substring carries the whole pin. Read that REJECT case
as pinning what the critic *says* when it rejects, never whether it rejects at
all. `outcome-table-in-prose` (2026-09-17) is the first REJECT case whose
token discriminates, and it does so against the second baseline only.

That is also why the 2026-08-18 cut took every REJECT case: the stub rejected
them all. A sample of five cut cases, re-ablated isolated on 2026-08-27,
mostly confirmed the cut. `plan-critic/collision`, `plan-critic/two-changes`,
`consolidate-critic/note-drift`, and `loop/mutation-no-critical-path` stay
no-ops, each answered correctly by the isolated stub 3/3. Only
`plan-critic/proof-altitude` moved, and only on its required substring: the
stub rejects 3/3 without ever writing the word "proof". That word is common
enough that one run is not evidence, so the case stays cut. The sample is what
closes the question the contaminated harness opened. Recovering the other 39 is
not worth the calls.

A REJECT case on this critic discriminates by its category word at best.
Two more drafts showed that on 2026-09-17. `baseline-never-stated` changes
shipped behaviour and never says what it is today. `ui-claim-unit-proof`
claims a browser flow and proves a unit function. The stub rejected both
3/3, and so did the prompt minus the bullet each one aims at. The cases
that discriminate here are the near misses, where a limiting clause stops a
false reject: `named-references`, `dep-refresh-no-red-test`, and
`thin-proof-right-level`. A fourth near miss, a new area with no baseline
to state, split both the critic and the stub 2/3 and pins nothing.

Three more near misses died on 2026-09-17, because everything approved
them: the critic, the stub, and the prompt minus the limiting clause. One
had a sibling slug beside an open Plan of the same area. One had an enum
column whose wider value space nobody can know yet. One proved a claim
about a form with a render test. A near miss discriminates only where the
stub invents an objection, and the stub found none in these three.

One more plan-critic draft died the same day. `refresh-handwritten-version`
hand-writes a version string into `package.json`. The stub rejected it 2/3,
so it is a no-op. A held-out paraphrase of `dep-refresh-no-red-test` died
too: the stub and the prompt minus the refresh bullet both approved it.

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

## Watch cases

A case dir named `*-watch` is in no suite run, with or without `--holdout`.
It runs only when `--cases` names it. A watch case is a brief on which a
paragraph still moves a tally and flips no plurality, so it cannot gate
anything today. It exists for the expiry check of a new model: run it at
five votes against the full prompt and against the prompt minus the
paragraph, and compare the tallies.

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

A claim that a prose cut "changed nothing" needs a number for how much the
suite moves when nothing changed. The measurement ran on 2026-09-01, on claude
2.1.252, with the critics on sonnet and loop and garden on opus. It made three
identical full-suite passes at `--votes 3` on one commit: 17 cases each, 153
votes in total. No plurality
verdict flipped across the passes (0/51). One single vote dissented:
`spike-note-may-age` went 2/3 (one CUTS vote) in the second pass and 3/3 in
the other two.

So on that date, a verdict flip after a prompt edit is signal, not sampling
noise. Two limits. The model aliases float, so the floor moves when the
provider re-points an alias. The run header shows the full model ID, so
compare it with the ID of the last measurement. Re-measure the floor before
an ablation campaign, and on every new model. And the one dissenting vote sits in
`spike-note-may-age`, the case pinned against hone's own deletion bias.
Read that case's tally first when a run degrades.

The floor was measured again on 2026-09-17, on claude 2.1.274, with the
critics on claude-sonnet-5 and loop and garden on claude-opus-5. Three
identical passes at `--votes 3` over the 19 visible cases gave 171 votes.
No plurality verdict flipped (0/57). Five single votes dissented. Three of
them were `spike-note-may-age` at 2/3 in every pass, and its entry above
has the cause and the fix. The other two were one REJECT vote each on
`dep-refresh-no-red-test` and `named-references`, both in the first pass.
So a flip is still signal. A 2/3 on a plan-critic APPROVE case is within
the noise, and a 2/3 on `spike-note-may-age` no longer is.

The floor was measured a third time on 2026-09-18, on claude 2.1.275,
with every target on claude-opus-5, after the critics' pins moved there.
Three identical passes at `--votes 3` over the 24 visible cases gave 216
votes. No plurality verdict flipped (0/72). One single vote dissented:
`thin-proof-right-level` gave one REJECT in the first pass, and its entry
above says why that brief still carries one fork. A pass cost about 3.80
dollars.

## Extending

Add a case whenever a critic misjudges a real change, or when the loop takes a
wrong turn. Capture the brief that fooled it, and the answer it should have
reached. Then ablate it before you keep it, with `run.sh` itself and never a
hand-rolled check. The scoring pools every vote that carried the verdict. So a
required substring that is merely on-topic can pass on one lucky vote, and a
per-vote check misses that. The `schema-silent-on-data` entry records one such
miss. A case that the stub answers
correctly is not a regression net, however real the misjudgment that prompted it.
