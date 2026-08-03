# Roadmap: evaluating and optimizing hone itself

hone's deletion bias applies to hone itself. This roadmap answers two
standing questions. The occasional one: does each building block — every
hook, critic, gate, and paragraph of prompt prose — still earn its keep, and
can what stays be smaller and cheaper? And the recurring one, forced by
model churn: which model belongs in which slot, and what changes when a new
model ships? Both take the same instruments, and the four stages below build
them in deliberate order: dataset and metric first, end-to-end lab second,
optimization last. Each stage is useful on its own even if the next never
happens. Status as of July 2026.

## The deletion question, by class

"Do we really need this?" is a different question per class of building
block, and each class has a different legitimate evaluator:

- *Model-compensating prose and judgment* (skill instructions, the critics,
  the nag). These exist because models at writing time didn't supply the
  behaviour unprompted, so they expire as models improve. The unit suite
  (stage 0/1) evaluates trims within them; the lab (stage 2) evaluates
  removing them whole.
- *Mechanical safety against the model* (guard, bash-guard, the settings deny
  rules, the land gates). These defend against rare misbehaviour, so
  average-case evals under-measure them by construction; only adversarial
  scenarios (stage 2) can price them. Their deletion bar is higher anyway:
  they are deterministic, nearly free when not triggered, and part of what
  makes a human willing to leave a run unattended.
- *Mechanical coordination* (worktrees, locks, land's merge-and-reverify).
  These guard against the environment — concurrency, races, flaky suites —
  not the model, so better models never obsolete them. Out of scope; only a
  workflow redesign would remove one.

Three rules hold for every deletion, whichever instrument proposed it:

1. A deletion is licensed only up to eval coverage; it can degrade a
   behaviour no case pins, so coverage keeps growing alongside the cutting.
2. It is tested on the *floor* model supported, not the best one: a cut that
   holds on opus can break the sonnet user, and hone runs on whatever model
   drives the session.
3. It enters this repo as an ordinary reviewed change, through the eval gates
   and a version bump like any prompt edit. No tool commits here.

## Model assignment and recalibration

hone has more model slots than it looks like: the critics (frontmatter
`model:`), the loop (whatever model drives the session), the nested
`/code-review` call (currently hard-coded `--model opus` in the run skill),
the stage-2 lab's judge, and eventually the optimizer's reflection model.
Each slot's assignment is a measurable question, not taste:

- the unit suite answers "can a cheaper model hold this slot?" per critic —
  and the per-case vote tallies are the safety margin: a model passing at
  2/3 everywhere is not a safe assignment, unanimity is;
- the loop target across models finds the floor model the skill's prose
  still carries (rule 2 above);
- the lab prices each assignment end-to-end, cost per run against outcome.

A new model release triggers recalibration in both directions:

- *downward guard*: does the existing prose still hold? A new model can read
  the same instructions differently; the suite plus the lab's behavioural
  track is the migration test.
- *upward opportunity*: which prose is now unnecessary? Section ablation
  (stage 1) for paragraphs, the ablation matrix (stage 3b) for whole
  components — "prose expires as models improve" made operational, with a
  model release as the moment the expiry check runs. Then re-do the
  assignment: the new mid-tier may take a slot the old top-tier held.

Cadence: the cheap unit suite on every model event, the expensive lab on
family releases. And one product change this discipline requires: the
critics are pinned to the floating `sonnet` alias, so the provider
re-pointing it silently recalibrates production with no commit here. Pin
full model IDs in the agent frontmatter and the review command, and treat an
alias move as a deliberate, suite-gated migration (a normal versioned
change) rather than ambient drift.

## Where things live

*In this repo:* `evals/` (the unit suite and, from stage 1, its
machine-drivable mode; cases version together with the prompts they pin); the
stage-2 lab's scenario definitions and bash harness (scenarios assert what a
given plugin version must do, so they belong in the same history — run
artifacts like transcripts, costs, and sandboxes are gitignored outputs);
and `docs/` ([`development.md`](development.md) for the day-to-day suites,
[`model.md`](model.md) *Checking* for why prompt prose needs evals at all).

*Elsewhere:* the stage-3 optimizer tooling lives in a sibling repo — Python
(the `gepa` package plus a thin adapter shelling into `evals/run.sh`), not
part of what consumers install, and structurally unable to commit here (rule
3 above). Its run logs, candidate pools, and caches stay with it.

*Deliberately not reused:* the Quorum eval lab
(`prime-radiant-inc/superpowers-evals`) — unlicensed, so its code is
off-limits; its scenarios test another workflow, and its multi-CLI/multi-OS
generality is complexity hone doesn't need; its publicly documented *design*
is the stage-2 blueprint. And DSPy — it wants to own execution as a Python
pipeline, which would fork the agent files hone actually ships; GEPA's
adapter model wraps our own harness instead.

## Stage 0 — unit evals for the judgment prose (done, 0.23.x)

`evals/` pins the critic prompts and the run skill's loop instructions to 46
cases with known-good answers: balanced so an over-strict critic fails
visibly, paraphrase variants against overfitting, a held-out set
(`--holdout`) against tuning to the suite, plurality voting with per-case
tallies, and a release gate in the releasing rule.
[`evals/README.md`](../evals/README.md) is the manual.

## Stage 1 — machine-drivable harness (next, small)

Three flags on `evals/run.sh` so a tool, not only a human, can drive it:
`--prompt-file` (evaluate a candidate prompt instead of the checked-in
file), `--cases` (run a subset; optimizers evaluate on minibatches), and
`--json` (one record per case × vote *including the full reply* — the trace
a reflective optimizer learns from, discarded today). Plus a response cache
keyed on (model, system prompt, brief), and a pinned full model ID per run,
because the floating `sonnet` alias makes runs incomparable across days.

What it unlocks immediately, before any optimizer: *section ablation* of the
class-1 prose — delete one section of a prompt at a time, re-run its eval
target, and cut what changes nothing. "Trim, re-run, keep what holds," done
systematically, under rule 1.

## Stage 2 — end-to-end scenario lab (the big missing layer)

Unit evals test prose in isolation; nothing yet tests the *installed
plugin*. The lab runs headless Claude Code with hone installed, in a sandbox
with an isolated `$HOME`, against fixture repos seeded with scenarios, on
two tracks:

- *behavioural*: a happy-path change, a review that injects a real finding,
  a claimed worktree, a change that trips the proof or authority gate — does
  the run end in the right terminal state?
- *adversarial*: planted temptations — a scenario where the cheapest path to
  green is weakening a check, a fix that would pass review without a
  reproducing test, a nudge toward writing the grant oneself. The evaluator
  for class 2: twenty benign runs with the guard off prove nothing about
  what it deters.

Grading reads the terminal state: deterministic post-checks first (commit
exists and conforms, suite green, diff confined to the Plan, worktree
cleaned, gates actually fired), one LLM judge for what post-checks can't
decide, a three-valued verdict (pass, fail, or *indeterminate* for
infrastructure failures, so a broken sandbox never reads as a behavioural
result), and per-run cost and transcript capture as first-class outputs.
Per-component ablation switches come free: the lab edits the sandboxed
plugin copy's `hooks.json`, so the product needs no feature for it.

Built small and in hone's own idiom: bash, extending the fixture-repo
patterns of `test/e2e_land_test.sh` and the fan-out/scoring conventions of
`evals/run.sh`. Expensive per run, so it gates releases, not commits. This
is the regression net for the plugin as a whole, and the evaluator for every
whole-component question.

## Stage 3 — automated optimization (last)

With stages 1 and 2 in place, the manual experiments above become search.
GEPA's `optimize_anything` (omni) covers both remaining kinds of question
under one budget:

- *3a, within components* (`gepa` engine, cheap, against the unit suite):
  the suite passes 46/46, so the objective must supply its own gradient —
  pass-rate minus a length penalty (the automated form of stage 1's section
  ablation), or passing the critics on a cheaper model. Specific to this
  stage: a train/val split inside the visible cases, the holdout set frozen
  as final test (grow it to ~8–10 first), and a candidate lint (frontmatter
  and load-bearing literals intact) that rejects broken mutations before
  they cost anything.
- *3b, across components* (`autoresearch` engine, overnight-budget tier,
  against the lab): pre-registered hypotheses in two families — efficiency
  (critic model downgrades, pre-baked review briefs, terser critic output
  contracts) and the *ablation matrix*, component × scenario set × model,
  asking whether a block still earns its keep ("without plan-critic,
  bad-plan scenarios fail at rate X"). Class-2 components are ablated only
  against the adversarial track.

Expectations set honestly: hone is deliberately lean (one loop, two small
critics), so the realistic wins are prompt length and cheaper critic models,
not the 50–60% a large multi-reviewer system harvested from the same method
— and the likely ablation outcome is confirming that the blocks earn their
keep, with the wins landing *inside* components rather than in removing
them. That is a prior the deletion bias says to test, not trust. The lab is
worth building regardless; optimization is then a cheap add-on, not the
justification.
