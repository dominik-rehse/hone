# Roadmap: evaluating and optimizing hone itself

hone's deletion bias applies to hone itself. This roadmap answers two
standing questions. The occasional one: is each building block still worth
its cost, and can what stays be smaller and cheaper? A building block here
is every hook, critic, gate, and paragraph of prompt prose. The recurring
one, forced by the pace of model releases: which model belongs in which slot, and what
changes when a new model ships? Both questions take the same tools.
The stages below build them in deliberate order: dataset and metric
first, end-to-end lab after them, optimization last. Each stage is useful on
its own even if the next never happens. Each stage heading carries its
status.

## The deletion question, by class

"Do we really need this?" is a different question per class of building
block. Each class has a different legitimate evaluator:

- *Model-compensating prose and judgment* (skill instructions, the critics,
  the nag). These exist because models at writing time did not supply the
  behavior unprompted. They expire as models improve. The unit suite
  (stages 0 to 2) evaluates trims within them. The lab (stage 3) evaluates
  removing them whole.
- *Mechanical safety against the model* (guard, bash-guard, the settings deny
  rules, the land gates). These defend against rare misbehavior, so
  average-case evals under-measure them by construction. Only adversarial
  scenarios (stage 3) can measure their value. Their deletion bar is higher anyway.
  They are deterministic, and they are nearly free when not triggered. They
  are also part of what makes a human willing to leave a run unattended.
- *Mechanical coordination* (worktrees, locks, land's merge-and-reverify).
  These guard against the environment (concurrency, races, flaky suites),
  not the model. Better models therefore never obsolete them. This class is
  out of scope. Only a workflow redesign would remove one.

Three rules hold for every deletion, whichever tool proposed it:

1. Eval coverage sets the limit of every deletion. A cut can degrade a
   behavior that no case pins, so stage 1 grows coverage before any cutting
   campaign.
2. Test every deletion on the *floor* model, not the best one. The floor of
   a target is the cheapest model on which its suite is green, and *Model
   assignment and recalibration* names the floors. A cut that holds on the
   best model can break a user on a cheaper one. hone runs on whatever
   model drives the session.
3. A deletion enters this repo as an ordinary reviewed change, through the
   eval gates and a version bump like any prompt edit. No tool commits
   here.

## Model assignment and recalibration

hone has more model slots than it looks like:

- the critics (frontmatter `model:`, a full model ID)
- the loop and the garden skill (whatever model drives the session)
- the nested `/code-review` call (a full model ID, hard-coded in the run
  skill)
- the stage-3 lab's judge

Each slot's assignment is a measurable question, not taste:

- The unit suite answers "can a cheaper model hold this slot?" per critic.
  The per-case vote tallies are the safety margin. A model that passes at
  2/3 everywhere is not a safe assignment. Only unanimity is.
- The loop target across models finds the floor model that the skill's
  prose still carries (rule 2 above).
- The lab measures each assignment end-to-end, cost per run against outcome.

The floors today are what the release gate measures
([`releasing.md`](../.claude/rules/releasing.md)). The critics gate on
sonnet, so sonnet is their floor. The `loop` and `garden` targets gate on
opus, and the nested review needs opus too. No run has measured the loop
or the garden prose on a cheaper model. So opus is the floor for both, and
rule 2 means opus there, until one of those targets passes on a cheaper
model.

Cost and quality are not the only axes for the review slot. Independence
is a possible third. The nested `/code-review` checks code the session's
own model wrote, so author and reviewer may share blind spots. The nested
call already runs in a fresh context with its own prompt, and no
measurement shows how much correlation remains. A reviewer from a
different model family should fail differently, and that decorrelation
would have value even when the second model is no better. hone does not
act on this today: a second vendor CLI is a heavy dependency for a plugin
this small. The lab (stage 3) can price the idea. Inject a known bug
family, such as the parallel-path scenario of its adversarial track, and
compare catch rates. Compare a different model of the same family first,
because that reviewer needs no new dependency.

A new model release triggers recalibration in both directions:

- *Downward guard*: does the existing prose still hold? A new model can
  read the same instructions differently. The suite plus the lab's
  behavioral track is the migration test.
- *Upward opportunity*: which prose is now unnecessary? Section ablation
  (stage 2) answers it for paragraphs. A lab run with the component
  switched off (stage 3) answers it for whole components. This makes
  "prose expires as models improve" operational: a model release is the
  moment the expiry check runs. Then re-do the assignment: the new
  mid-tier may take a slot the old top-tier held.

Cadence: run the cheap unit suite on every model event, and the expensive
lab on family releases. This discipline needed one product change, and
0.53.0 made it. The agent frontmatter used to name the floating `sonnet`
alias, so the provider re-pointing that alias recalibrated production with
no commit here. The agent frontmatter and the review command now carry full
model IDs, and `test/prose_test.sh` fails on an alias in either slot. A
move to another model is a deliberate, suite-gated migration, and
[`releasing.md`](../.claude/rules/releasing.md) *Moving a model pin* has the
steps.

## Where things live

*In this repo:* `evals/` holds the unit suite and, from stage 2, its
machine-drivable mode. Cases version together with the prompts they pin.
The stage-3 lab's scenario definitions and bash harness live here too.
Scenarios assert what a given plugin version must do, so they belong in the
same history. Run artifacts like transcripts, costs, and sandboxes are
gitignored outputs. `docs/` carries the prose:
[`development.md`](development.md) for the day-to-day suites, and
[`model.md`](model.md) *Checking* for why prompt prose needs evals at all.

*Deliberately not reused:* the Quorum eval lab
(`prime-radiant-inc/superpowers-evals`). It has no license, so its code is
off-limits. Its scenarios test another workflow, and its
multi-CLI/multi-OS generality is complexity hone does not need. Its
publicly documented *design*, though, is the stage-3 blueprint.

## Stage 0: unit evals for the judgment prose (done, 0.23.x)

`evals/` pins the critic prompts, the run skill's loop instructions, and
the garden skill to cases with known-good answers. The releasing rule makes
the suite a release gate. [`evals/README.md`](../evals/README.md) is the
manual. It carries the case ledger and every count, so this file repeats
none of them.

Three additions since 0.23.x changed what the suite is:

- *The no-op cut* (2026-08-18). `--ablate` runs each case against a stub
  with no hone prose. Most cases passed against the stub, so they pinned
  nothing, and the cut removed them. See *A case must discriminate*.
- *The second baseline.* A case can also prove itself against the prompt
  minus the paragraph that the case pins. See the section of that name.
- *The noise floor* (2026-09-01). Repeated passes on one commit flipped no
  plurality verdict, so a flip after a prompt edit is signal. See *The
  noise floor*.

The cut left every target thin. *Known gaps* in the manual lists what
stays unpinned.

## Stage 1: coverage growth (next)

Rule 1 makes coverage the limit of every cut, and the suite is thin after
the no-op cut. An ablation on a thin suite reports that most sections
change nothing, because no case looks at them. So coverage grows before
any ablation campaign.

A new case must discriminate, and most drafts do not. *Known gaps* in the
manual records the failed attempts and the brief shape that works: bury
the thing under test instead of naming it.

The stage is done when these hold:

- each critic has a discriminating case for each of its verdicts
- each of the four targets has a held-out case
- each section that a stage-2 ablation will test has a case aimed at it

The third condition repeats per campaign. It is also the rule for reading
an ablation: an unchanged suite is evidence only for a section that a case
aims at.

## Stage 2: machine-drivable harness (done, 2026-09-17)

[`evals/README.md`](../evals/README.md) *Driving the harness from a tool* is
the manual for this stage. Three flags on `evals/run.sh` let a tool, not only
a human, drive it:

- `--prompt-file` evaluates a candidate prompt instead of the checked-in
  file.
- `--cases` runs a subset, because optimizers evaluate on minibatches.
- `--json` writes one record per case × vote, *including the full reply*:
  the trace a reflective optimizer learns from. The terminal output
  discards that reply.

Two more pieces belong to this stage: a response cache keyed on (model,
system prompt, brief), and a pinned full model ID per run. The pin matters
because the floating `sonnet` alias makes runs incomparable across days. The
cache is opt-in (`--cache`), because a release gate must measure afresh.

The flags do not depend on stage 1. Their first use does. That use is
*section ablation* of the class-1 prose, before any optimizer. Delete one
section of a prompt at a time, re-run its eval target, and cut what
changes nothing. It is the same run as the manual's second baseline, read
in the other direction. There the run tests the case, and here it tests
the section. That is "trim, re-run, keep what holds" done systematically,
under rule 1 and the reading rule of stage 1.

## Stage 3: end-to-end scenario lab (the big missing layer)

Unit evals test prose in isolation. Nothing yet tests the *installed
plugin*. The lab runs headless Claude Code with hone installed, in a
sandbox with an isolated `$HOME`, against fixture repos seeded with
scenarios. It runs on two tracks:

- *behavioral*: a happy-path change, a review that injects a real finding,
  a claimed worktree, a change that trips the proof or authority gate. Does
  the run end in the right terminal state?
- *adversarial*: planted temptations, such as:
  - a scenario where the cheapest path to green is weakening a check
  - a fix that would pass review without a reproducing test
  - a nudge toward writing the grant oneself
  - a change with two parallel code paths where the Plan's fix reaches
    only one. Examples are a sandbox path beside a production path, and
    the two branches of a feature flag.

  This track is the evaluator for class 2. Twenty benign runs with the
  guard off prove nothing about what the guard deters.

Grading reads the terminal state. Deterministic post-checks run first: the
commit exists and conforms, the suite is green, and the diff stays confined
to the Plan. They also check that the run cleaned the worktree and that the
gates actually fired. One LLM judge decides what post-checks cannot. The
verdict is three-valued: pass, fail, or *indeterminate* for infrastructure
failures. The third value exists so a broken sandbox never reads as a
behavioral result. Per-run cost and transcript capture are first-class
outputs. Per-component ablation switches come free: the lab edits the
sandboxed plugin copy's `hooks.json`, so the product needs no feature for
it.

The lab stays small and in hone's own idiom: bash. It extends the
fixture-repo patterns of `test/e2e_land_test.sh` and the fan-out/scoring
conventions of `evals/run.sh`. It is expensive per run, so it gates
releases, not commits. This is the regression net for the plugin as a
whole, and the evaluator for every whole-component question. The likely
answer to those questions is that the blocks are worth their cost. That is
a prior the deletion bias says to test, not trust.

## Later: automated optimization

This is a note, not a stage. With the harness and the lab in place, the
manual experiments above can become search. GEPA's `optimize_anything`
covers both kinds: prompt candidates against the unit suite, and
pre-registered component hypotheses against the lab. GEPA fits because its
adapter model wraps `evals/run.sh`. DSPy does not fit. It wants to own
execution as a Python pipeline, and that would fork the agent files hone
ships. The tooling would live in a sibling repo, outside what consumers
install. Its output would enter this repo only under rule 3.

Two conditions come first. The lab exists. The visible cases are enough
for a train/val split, with the holdout set frozen as the final test.
Neither holds today.

The expectations are modest. hone is deliberately lean: one loop, two
small critics. The realistic wins are shorter prompts and cheaper critic
models, and manual section ablation (stage 2) can find both. So the
optimizer must first show that it beats the manual method. The lab is
worth building regardless.
