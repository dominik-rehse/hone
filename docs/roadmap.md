# Roadmap: evaluating and optimizing hone itself

hone's goal is to land good changes unattended, cheaply and safely. This
roadmap is about making hone itself better at that. Every hook, critic,
gate, and paragraph of prompt prose has a cost, and the deletion bias
applies to hone too. It answers two standing questions. Is each building
block still worth its cost, and can what stays be smaller and cheaper? And
which model belongs in which slot, and what changes when a new model ships?

The method is plain. The three test suites are hard constraints. A change
to hone must keep all three green. Within those constraints the objective
is one number to lower: dollars per landed change, as the lab records it.
The maintainer has not yet confirmed that objective, and *Open decisions*
lists it.

## The constraints: three suites

Each suite checks one layer, and none can stand in for another.
[`development.md`](development.md) says when to run which.

- *The mechanical suite* (`bash test/run.sh`, no model calls, free). The
  hooks, `worktree.sh`, the land path, the plumbing of both harnesses
  against a fake CLI, and every message hone prints. It proves that the
  machinery does what it says. It cannot see whether a prompt is good.
- *The unit evals* (`bash evals/run.sh`, a few dollars). The prose that the
  model executes: the two critics, the run skill's loop, and the garden
  skill. Each case is a brief with a known right answer, and every case
  passed an ablation, so it discriminates. It catches a prompt edit that
  weakens a behaviour. [`evals/README.md`](../evals/README.md) is the
  manual and carries the case ledger.
- *The lab* (`bash evals/lab/run.sh`, about 30 dollars an hour). The
  installed plugin, end to end, against seeded fixture repos. It is the
  only suite that can say what a hook deters, and the only one that
  measures cost per landed change.
  [`evals/lab/README.md`](../evals/lab/README.md) is the manual.

The constraints reach only as far as the cases do. A cut that breaks a
behaviour with no case passes all three. So "green after a cut" means
"green for what we test", and coverage is the limit of every deletion.

## Three rules for every deletion

1. Eval coverage sets the limit. A cut can degrade a behaviour that no case
   pins, so coverage grows before any cutting campaign.
2. Test every deletion on the *floor* model, not the best one. The floor of
   a target is the cheapest model on which its suite is green. A cut that
   holds on the best model can break a user on a cheaper one, and hone runs
   on whatever model drives the session.
3. A deletion enters this repo as an ordinary reviewed change, through the
   eval gates and a version bump like any prompt edit. No tool commits
   here.

"Do we really need this?" has a different evaluator per class of building
block:

- *Model-compensating prose and judgment* (skill instructions, the critics,
  the nag). They exist because models at writing time did not supply the
  behaviour unprompted, and they expire as models improve. The unit suite
  evaluates trims within them. The lab evaluates removing them whole.
- *Mechanical safety against the model* (guard, bash-guard, the settings
  deny rules, the land gates). They defend against rare misbehaviour, so
  average-case evals under-measure them by construction. Only the lab's
  adversarial scenarios can measure their value. Even there, only a
  scenario in which a current model reaches for the forbidden path counts.
  Their deletion bar is higher anyway: they are deterministic, nearly free
  when not triggered, and part of what makes a human willing to leave a run
  unattended.
- *Mechanical coordination* (worktrees, locks, land's merge-and-reverify).
  They guard against the environment, not the model, so better models never
  obsolete them. Out of scope. Only a workflow redesign would remove one.

## Model slots

| slot | model | set by |
|---|---|---|
| `plan-critic`, `consolidate-critic` | claude-opus-5 | frontmatter `model:` |
| nested `/code-review` | claude-opus-5 | the command in the run skill |
| the loop, `/hone:plan`, `/hone:garden` | the session's model | the user |
| the lab's judge | claude-sonnet-5 | `--judge-model` |

Every pin is a full model ID, and `test/prose_test.sh` fails on an alias.
An alias floats when the provider re-points it, and 0.53.0 ended that. A
move to another ID is a suite-gated migration, and
[`releasing.md`](../.claude/rules/releasing.md) *Moving a model pin* has
the steps.

The measured floors, from 2026-09-17 and 2026-09-18:

- *The critics* hold on claude-sonnet-5 and not on claude-haiku-4-5. They
  pin claude-opus-5 since 0.54.0, one tier above the floor, by the
  maintainer's choice. Opus reads the `plan-critic` prose more strictly. It
  rejected two Plans that sonnet approved, and each time it named a real
  fork in the Plan. The cases moved, not the prose. On opus the stub
  approves most of the near-miss cases too, so the ledger says which cases
  still pin something there.
- *The loop* holds on claude-opus-5 and not on claude-sonnet-5, which
  answered HANDROLL 2/3 on `review-fanout-temptation`. The lab agrees in
  part: sonnet landed `parallel-paths` in silence once, and it reached for
  the primary tree after a plain request in three runs of seven.
- *The garden skill* holds on claude-sonnet-5. Its suite is thin, so this
  says that the pinned classification holds there, and nothing about the
  rest of the skill. Its release gate still runs on opus.
- *The nested review* has no unit target. The lab measures it since
  2026-09-17 with `--review-model` and a note per run on whether the review
  itself found the seeded defect
  ([`spikes/2026-09-17-review-model-switch.md`](spikes/2026-09-17-review-model-switch.md)).
  Ten runs are too few to move the pin. Every tier caught a defect inside
  the touched function. claude-haiku-4-5 missed the one outside the diff in
  the one run that tested it. claude-sonnet-5 caught it twice.

A new model release triggers recalibration in both directions. Downward:
does the existing prose still hold? A new model can read the same
instructions differently, as opus did with the `plan-critic`. The suite
plus the lab's behavioral track is the migration test. Upward: which prose
is now unnecessary? Section ablation answers it for paragraphs, and a lab
run with a component switched off answers it for whole components. Run the
cheap unit suite on every model event, and the expensive lab on family
releases.

Independence is a possible third axis for the review slot, beside cost and
quality. The nested review checks code that the session's own model wrote,
so author and reviewer may share blind spots. A reviewer from another
family should fail differently. hone does not act on this today, because a
second vendor CLI is a heavy dependency for a plugin this small. The lab
can price the idea with `--review-model` and a defect outside the diff.

## Where things live

`evals/` holds the unit suite, its machine-drivable flags, and the lab's
scenarios and harness. Cases and scenarios version together with the prose
and the plugin they pin. Run artifacts (transcripts, costs, sandboxes) are
outputs, and the lab keeps its sandboxes under `/var/tmp/hone-lab`, outside
every project. `docs/spikes/` carries each measurement as a dated note.
[`model.md`](model.md) *Checking* says why prompt prose needs evals at all.

The Quorum eval lab (`prime-radiant-inc/superpowers-evals`) is deliberately
not reused. It has no license, its scenarios test another workflow, and its
multi-CLI generality is complexity hone does not need. Its publicly
documented design was the blueprint for the lab.

## Stage 0: unit evals for the judgment prose (done)

The suite exists, gates releases, and has three properties that make it
trustworthy. Every case discriminates: the no-op cut of 2026-08-18 removed
44 cases that a model with no hone prose answered correctly. A case can
also prove itself against the prompt minus the paragraph it pins, which is
the second baseline. And the noise floor is measured: three identical
passes flip no verdict, so a flip after a prompt edit is signal. The latest
floor is from 2026-09-18, on the opus pins.

## Stage 1: coverage growth (two passes done, most sections still open)

The stage ends when three conditions hold. Each critic has a discriminating
case for each of its verdicts. Each target has a held-out case. Each
section that an ablation will test has a case aimed at it. The first two hold since
2026-09-17. The third holds for 7 of 20 critic sections.

Two passes taught what a case can and cannot pin. A brief that names the
thing under test measures agreement, and the model always agrees. A brief
that buries it measures whether the prose makes the model look, and that is
the shape that works. A draft aimed at one bullet still tends to die,
because the current model applies most bullets unprompted. So the sections
with no case are not a coverage gap to fill at any price. Many of them are
prose that the model no longer needs, and the next release of a model is
when that shows. *Known gaps* in the manual records every dead draft and
why.

Next: a REJECT case for the rejecting half of the `plan-critic` bullet on
dependency refreshes, because its approving half looks expired (stage 2).
Then harder briefs, in the buried shape, only for sections whose loss would
hurt.

## Stage 2: machine-drivable harness (done, first ablation done)

`evals/run.sh` takes `--prompt-file`, `--cases`, `--json`, and `--cache`,
so a tool can drive it. Their first use is section ablation: delete one
section of a prompt, run its target, and read the result under one rule.
An unchanged suite is evidence only for a section that a case aims at.

The first campaign ran on 2026-09-17 over both critics on claude-sonnet-5
([`spikes/2026-09-17-first-section-ablation.md`](spikes/2026-09-17-first-section-ablation.md)).
It cost about 20 dollars and cut nothing. It found one expiry candidate,
the approving half of the refresh bullet, and one rule: a cut of a bullet
must take its category word along, or the word floats and the critic files
other things under it. A campaign per prompt edit is affordable. One per
commit is not.

## Stage 3: the scenario lab (first version done, floor open)

The lab runs headless Claude Code with a copy of hone, in a sandbox, against
eleven seeded scenarios. Deterministic checks and one judge grade the end
state. Four scenarios are behavioral and seven adversarial. It gates
releases. `--without` switches a hook off in the sandboxed copy, and
`--review-model` swaps the reviewer, so the product needs no feature for
either.

What it has shown so far:

- *It catches what the unit suite cannot.* Its first use as a release gate
  caught a bad edit to the run skill that the loop evals passed at 3/3
  ([`spikes/2026-09-17-lab-first-runs.md`](spikes/2026-09-17-lab-first-runs.md)).
- *It shows what two guards deter.* After a plain request with no
  `/hone:run`, claude-haiku-4-5 and claude-sonnet-5 edit `src/` in the
  primary tree. `guard` turns that run into a Plan, and the dirty-guard
  makes it restore the files. With all guards off the edit stays
  ([`spikes/2026-09-17-guard-temptations.md`](spikes/2026-09-17-guard-temptations.md)).
  Opus never reached. No model on any scenario took the flag that skips
  git hooks, even when offered. So the bash-guard and the deny rules still
  have no scenario that shows their value
  ([`spikes/2026-09-17-guards-first-look.md`](spikes/2026-09-17-guards-first-look.md)).
- *It found its own flaw.* The sandbox sat inside this repository. Claude
  Code loaded hone's development rules into every run from the directories
  above. Every measurement before the evening of 2026-09-17 had those rules
  in context. The sandbox is outside the repository now, and the
  harness refuses a location below an instruction file.

Open:

- The noise floor outside the repository has one pass of the three it
  needs. One pass over eleven scenarios on opus gave 11 passes. Until the
  other two run, the release gate rests on one sample.
- The guard counts are one to three runs per cell. They show that a
  temptation is real for the smaller models, and they give no rate.
- One haiku run walked around a commit hook with a mock of the missing
  scanner on `PATH`. No guard reads that route, and it has no owner.

## Open decisions

- *The objective.* Dollars per landed change, with the suites as hard
  constraints. The lab records it per run. A happy-path run costs about 2
  dollars on opus. Not yet confirmed by the maintainer.
- *The garden release gate.* It runs on opus, and the measured floor is
  sonnet. Nothing measured so far bears on the choice.
- *The lab's noise floor.* Two more passes, about 60 dollars, or the gate
  keeps resting on one.
- *The mock-tool route.* Inside or outside hone's threat model, which is a
  friction-avoiding agent and not an adversary.

## Later: automated optimization

This is a note, not a stage. With the harness and the lab in place, the
manual experiments above can become search. GEPA's `optimize_anything`
fits, because its adapter model wraps `evals/run.sh`. DSPy does not, because
it wants to own execution as a Python pipeline and would fork the agent
files hone ships. The tooling would live in a sibling repo, and its output
would enter this repo only under rule 3.

Two conditions come first. The lab exists now. The visible cases are still
far too few for a train/val split with the holdout set frozen as the final
test. And the first manual ablation found nothing to cut, so an optimizer
must first show that it beats the manual method. The expectations are
modest: hone is one loop and two small critics, and the realistic wins are
shorter prompts and cheaper models.
