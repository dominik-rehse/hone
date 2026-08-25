# Roadmap: evaluating and optimizing hone itself

hone's deletion bias applies to hone itself. This roadmap answers two
standing questions. The occasional one: is each building block still worth
its cost, and can what stays be smaller and cheaper? A building block here
is every hook, critic, gate, and paragraph of prompt prose. The recurring
one, forced by the pace of model releases: which model belongs in which slot, and what
changes when a new model ships? Both questions take the same tools.
The four stages below build them in deliberate order: dataset and metric
first, end-to-end lab second, optimization last. Each stage is useful on
its own even if the next never happens. Status as of July 2026.

## The deletion question, by class

"Do we really need this?" is a different question per class of building
block. Each class has a different legitimate evaluator:

- *Model-compensating prose and judgment* (skill instructions, the critics,
  the nag). These exist because models at writing time did not supply the
  behavior unprompted. They expire as models improve. The unit suite
  (stage 0/1) evaluates trims within them. The lab (stage 2) evaluates
  removing them whole.
- *Mechanical safety against the model* (guard, bash-guard, the settings deny
  rules, the land gates). These defend against rare misbehavior, so
  average-case evals under-measure them by construction. Only adversarial
  scenarios (stage 2) can measure their value. Their deletion bar is higher anyway.
  They are deterministic, and they are nearly free when not triggered. They
  are also part of what makes a human willing to leave a run unattended.
- *Mechanical coordination* (worktrees, locks, land's merge-and-reverify).
  These guard against the environment (concurrency, races, flaky suites),
  not the model. Better models therefore never obsolete them. This class is
  out of scope. Only a workflow redesign would remove one.

Three rules hold for every deletion, whichever tool proposed it:

1. Eval coverage sets the limit of every deletion. A cut can degrade a
   behavior that no case pins, so coverage keeps growing alongside the
   cutting.
2. Test every deletion on the *floor* model supported, not the best one. A
   cut that holds on opus can break the sonnet user. hone runs on whatever
   model drives the session.
3. A deletion enters this repo as an ordinary reviewed change, through the
   eval gates and a version bump like any prompt edit. No tool commits
   here.

## Model assignment and recalibration

hone has more model slots than it looks like:

- the critics (frontmatter `model:`)
- the loop (whatever model drives the session)
- the nested `/code-review` call (currently hard-coded `--model opus` in
  the run skill)
- the stage-2 lab's judge
- eventually, the optimizer's reflection model

Each slot's assignment is a measurable question, not taste:

- The unit suite answers "can a cheaper model hold this slot?" per critic.
  The per-case vote tallies are the safety margin. A model that passes at
  2/3 everywhere is not a safe assignment. Only unanimity is.
- The loop target across models finds the floor model that the skill's
  prose still carries (rule 2 above).
- The lab measures each assignment end-to-end, cost per run against outcome.

A new model release triggers recalibration in both directions:

- *Downward guard*: does the existing prose still hold? A new model can
  read the same instructions differently. The suite plus the lab's
  behavioral track is the migration test.
- *Upward opportunity*: which prose is now unnecessary? Section ablation
  (stage 1) answers it for paragraphs. The ablation matrix (stage 3b)
  answers it for whole components. This makes "prose expires as models
  improve" operational: a model release is the moment the expiry check
  runs. Then re-do the assignment: the new mid-tier may take a slot the
  old top-tier held.

Cadence: run the cheap unit suite on every model event, and the expensive
lab on family releases. This discipline also requires one product change.
The agent frontmatter pins the critics to the floating `sonnet` alias, so
the provider re-pointing that alias silently recalibrates production with
no commit here. Pin full model IDs in the agent frontmatter and the review
command. Treat an alias move as a deliberate, suite-gated migration (a
normal versioned change) rather than a silent change.

## Where things live

*In this repo:* `evals/` holds the unit suite and, from stage 1, its
machine-drivable mode. Cases version together with the prompts they pin.
The stage-2 lab's scenario definitions and bash harness live here too.
Scenarios assert what a given plugin version must do, so they belong in the
same history. Run artifacts like transcripts, costs, and sandboxes are
gitignored outputs. `docs/` carries the prose:
[`development.md`](development.md) for the day-to-day suites, and
[`model.md`](model.md) *Checking* for why prompt prose needs evals at all.

*Elsewhere:* the stage-3 optimizer tooling lives in a sibling repo. It is
Python: the `gepa` package plus a thin adapter shelling into
`evals/run.sh`. It is not part of what consumers install, and it is
structurally unable to commit here (rule 3 above). Its run logs, candidate
pools, and caches stay with it.

*Deliberately not reused:* the Quorum eval lab
(`prime-radiant-inc/superpowers-evals`) and DSPy. The Quorum lab has no
license, so its code is off-limits. Its scenarios test another workflow.
Its multi-CLI/multi-OS generality is complexity hone does not need. Its
publicly documented *design*, though, is the stage-2 blueprint. DSPy wants
to own execution as a Python pipeline, and that would fork the agent files
hone actually ships. GEPA's adapter model wraps our own harness instead.

## Stage 0: unit evals for the judgment prose (done, 0.23.x)

`evals/` pins the critic prompts and the run skill's loop instructions to
46 cases with known-good answers. The suite is balanced, so an over-strict
critic fails visibly. Paraphrase variants work against overfitting. A
held-out set (`--holdout`) works against tuning to the suite. Voting is by
plurality, with per-case tallies. The releasing rule makes the suite a
release gate. [`evals/README.md`](../evals/README.md) is the manual.

## Stage 1: machine-drivable harness (next, small)

Three flags on `evals/run.sh` let a tool, not only a human, drive it:

- `--prompt-file` evaluates a candidate prompt instead of the checked-in
  file.
- `--cases` runs a subset, because optimizers evaluate on minibatches.
- `--json` writes one record per case × vote, *including the full reply*:
  the trace a reflective optimizer learns from. Today the runner discards
  that reply.

Two more pieces belong to this stage: a response cache keyed on (model,
system prompt, brief), and a pinned full model ID per run. The pin matters
because the floating `sonnet` alias makes runs incomparable across days.

It unlocks one thing immediately, before any optimizer: *section ablation*
of the class-1 prose. Delete one section of a prompt at a time, re-run its
eval target, and cut what changes nothing. That is "trim, re-run, keep
what holds" done systematically, under rule 1.

## Stage 2: end-to-end scenario lab (the big missing layer)

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
whole, and the evaluator for every whole-component question.

## Stage 3: automated optimization (last)

With stages 1 and 2 in place, the manual experiments above become search.
GEPA's `optimize_anything` (omni) covers both remaining kinds of question
under one budget:

- *3a, within components* (`gepa` engine, cheap, against the unit suite).
  The suite passes 46/46, so the objective must supply its own gradient.
  That gradient is pass-rate minus a length penalty, or passing the
  critics on a cheaper model. The length penalty is the automated form of
  stage 1's section ablation. Specific to this stage:
  - a train/val split inside the visible cases
  - the holdout set frozen as final test (grow it to ~8–10 first)
  - a candidate lint, which checks that frontmatter and load-bearing
    literals are intact and rejects broken mutations before they cost
    anything
- *3b, across components* (`autoresearch` engine, overnight-budget tier,
  against the lab). This stage tests pre-registered hypotheses, in two
  families. One is efficiency: critic model downgrades, pre-baked review
  briefs, terser critic output contracts. The other is the *ablation
  matrix*, component × scenario set × model. It asks whether a block is
  still worth its cost ("without plan-critic, bad-plan scenarios fail at rate
  X"). The matrix ablates class-2 components only against the adversarial
  track.

The expectations are modest. hone is deliberately lean: one loop, two
small critics. So the realistic wins are prompt length and cheaper critic
models, not the 50–60% a large multi-reviewer system gained from the
same method. The likely ablation outcome is confirming that the blocks
are worth their cost, with the wins landing *inside* components rather than in
removing them. That is a prior the deletion bias says to test, not trust.
The lab is worth building regardless. Optimization is then a cheap add-on,
not the justification.
