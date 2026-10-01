# Developing hone

This page is for changing the plugin itself. [`model.md`](model.md) (why it
works this way) and [`reference.md`](reference.md) (the control surface)
cover using hone in a project. [`roadmap.md`](roadmap.md) has the open
items.

## What ships and what doesn't

hone reaches consumers through its marketplace entry, so an install is
exactly what `.claude-plugin/plugin.json` describes: `rules/`, `skills/`,
`hooks/`, `agents/`, `scripts/`, and `templates/`. Everything else is
repo-internal and never reaches a consumer: `README.md`, `test/`, `evals/`,
`docs/`, and `.claude/` (this repo's own settings and rules). `README.md`
is the only one of those a stranger reads, because GitHub and the
marketplace listing show it, so it is repo-internal without being private.

The consequence that shapes every change: consumers only pick up a change
through a marketplace version bump. An edit to a distributed file that
ships without a bump reaches nobody. The bump rule lives in
[`.claude/rules/releasing.md`](../.claude/rules/releasing.md), and Claude
Code loads it automatically in this repo. If your session did not load it,
read that file before releasing.

## The three suites

Which suite a change must pass follows from what it touches.

*Mechanical*: `bash test/run.sh`. It is deterministic and makes no model
calls. It covers:

- the hook unit tests
- the end-to-end land path (worktree, gates, merge, fast-forward)
- the plumbing of the eval harness and of the lab, against a fake CLI
- the prose and the shape of every message in `hooks/messages.sh`

Every release runs this suite. Run it after any change to `hooks/`,
`scripts/`, `evals/run.sh`, or `evals/lab/` too. The shell sources also stay
`shellcheck`-clean (`.shellcheckrc` sets the dialect). Nothing runs
shellcheck for you, so run it over any script you touch.

*Judgment*: `bash evals/run.sh`. This suite calls models. It pins the
critic prompts and the run skill's loop instructions to cases with
known-good answers. [`evals/README.md`](../evals/README.md) is the manual:
targets and cases, the balance between reject and near-miss pass cases,
plurality voting, and the held-out cases. Two rules matter most. Match the
model to what runs in production. The critic frontmatter names the `opus`
alias, and the harness defaults to it. The loop and garden targets run with
`--model opus`. And never read or tune against a `*-holdout` case while
editing prose.

*End to end*: `bash evals/lab/run.sh`. The scenario lab runs the whole
plugin headless against fixture repos and grades the state each run leaves.
It calls models for minutes per scenario. So no release and no commit runs
it. It runs on the maintainer's word, and once for each new Opus.
[`evals/lab/README.md`](../evals/lab/README.md) is the manual.

There is no CI. The suites run locally, and the releasing rule is what
makes them a gate.

## Judging a change to hone

A change to hone is a claim about the codebases that hone leaves behind.
[*Goals*](model.md#goals) names the eight outcomes. This table says what
pursues each one and what measures it.

| Outcome | Pursued by | Measured by |
| --- | --- | --- |
| Transparent | guard, consolidate and its critic, nag, garden | lab `seeded-prose`: `note_spec`, `decision_restates`. Lab `untied-sentence`: `docs_true` |
| Well structured | *Type first* at build, the rule of three, the critic | lab `seeded-structure`: `format_copies`, `status_fact`. Lab `python-structure`: `dup gone`, `cc_pile flat` |
| Correct | test-first work, gate, nested review, land gates | lab end-state checks, `review_named` |
| Safe | hooks, deny rules, the loop's stop rules | the lab's adversarial track with `reached`, the loop evals |
| Reversible | one worktree and one merge per change, the grant gate | lab check `revertible` |
| Predictable | the fixed loop, as a side effect | `ending` in each `result.json` |
| Human attention | one Plan, a critic at plan time, a stop that names one action | `ending`, `stop_actionable`, `bounced` of lab `plan-clear` and `plan-fork`, the APPROVE cases of `plan-critic` |
| Dollars and minutes | nothing on purpose | cost and time in each `result.json` |

[`evals/lab/README.md`](../evals/lab/README.md) explains each scenario and
each measure.

### The rules

1. *Coverage is the limit.* A change can degrade an outcome that nothing
   measures. So the measurements grow before a campaign of changes.
2. *A change enters as a reviewed change.* No tool commits here.
3. *A change carries its upgrade path.* A consumer repo holds state that
   hone wrote. That state is the adapters, the policy files, the settings
   block, and the docs shapes. A change to it needs one of three paths:
   - *None needed*, because no consumer state changes.
   - *Mechanical*: `scripts/setup.sh` or a `/hone:garden` pass carries it,
     with a test that starts from the old shape.
   - *Manual*: [`upgrading.md`](upgrading.md) names a step for a person,
     and the step counts as human attention.

   A release without a path is not complete.
4. *A cheap, deterministic check needs no measured gain.* Cheap means
   three things. It makes no model call. It ships no new tool. It is
   exact. Such a check enters on its own tests and its upgrade path. A heuristic that can misfire costs human
   attention, so it must show a gain.

Each class of building block has its own evaluator:

- *Prose and judgment* (the skills, the critics, the nag). They make up
  for what a model does not do unprompted, and they expire as models
  improve. The unit suite judges a trim. The lab judges a removal.
- *Safety against the model* (the guards, the deny rules, the land
  gates). Only a lab scenario in which the model reaches for the forbidden
  path measures them. Haiku and sonnet reach for that path more often
  than opus, so such a scenario may run on them.
- *Coordination* (worktrees, locks, land's merge and re-verify). They
  guard against the environment, not the model. They are out of scope.

### What an evaluation costs

The figures are API prices from 2026-09-18 on claude-opus-5. The account
is on the Max plan, so the real limit is the plan's usage.

- The mechanical suite: no model call, a few minutes.
- One unit target at three votes: 1 to 3 dollars. The whole unit suite
  costs about 4 dollars.
- One full lab pass: about 36 dollars and 65 minutes.

## Changing judgment prose

The critic prompts (`agents/`), the run skill and its references
(`skills/run/`), and the injected rule (`rules/workflow.md`) are behavior,
not documentation. Treat an edit to them like a code change. Run the
relevant eval target before and after the edit. When a critic misjudges a
real change or the loop takes a wrong turn, capture it as a new case.
*Extending* in [`evals/README.md`](../evals/README.md) shows how. The same
suite is what makes *deleting* prose safe as models improve: trim, re-run,
and keep what holds.

## Change briefs

A brief for work on hone itself lives at `.plans/<slug>.md`, in the shape the
`plan` skill defines. This repo is not self-hosted, so no loop executes the
brief and no consolidate deletes it. A human does both. The brief is still
tracked, still one file, and still gone from the tree once the work lands. The
commit that finishes the work deletes it, and git history keeps it. Do not
invent a second place or a second shape for the same artifact.

The `plan-critic` has usually not seen such a brief. Say so in the brief when
it has not.

## Docs

`docs/` here follows the same honing hone enforces elsewhere: `model.md`
carries the why, and `reference.md` carries the detail. When the two
disagree, `reference.md` wins, and the other page is the bug. A behavior
change is not done until the same commit updates the page that describes
the old behavior.
