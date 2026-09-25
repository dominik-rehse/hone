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
- the candidate procedure, against hand-written results
- the prose and the shape of every message in `hooks/messages.sh`

Run this suite after any change to `hooks/`, `scripts/`, `evals/run.sh`,
`evals/candidate.sh`, or `evals/lab/`. The shell sources also stay
`shellcheck`-clean (`.shellcheckrc` sets the dialect). Nothing runs
shellcheck for you, so run it over any script you touch.

*Judgment*: `bash evals/run.sh`. This suite calls models. It pins the
critic prompts and the run skill's loop instructions to cases with
known-good answers. [`evals/README.md`](../evals/README.md) is the manual:
targets and cases, the balance between reject and near-miss pass cases,
plurality voting, and the held-out set discipline. Two rules matter most.
Match the model to what runs in production. The critic frontmatter names the
`opus` alias, and the harness defaults to it. The loop target runs with
`--model opus`. The garden target runs on opus and on its floor, sonnet.
And never read or tune against a `*-holdout` case while editing prose.

*End to end*: `bash evals/lab/run.sh`. The scenario lab runs the whole
plugin headless against fixture repos and grades the state each run leaves.
It calls models for minutes per scenario, so it is for a release and never
for a commit. [`evals/lab/README.md`](../evals/lab/README.md) is the manual.

There is no CI. The suites run locally, and the releasing rule is what
makes them a gate.

A change that is meant to make hone better, smaller, or cheaper is a
*candidate*. `bash evals/candidate.sh plan` names the suites that it owes
and their cost, and `decide` reads the results of both arms and answers
accept, reject, or undecided. *Judging a change to hone* below has the
rules.

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
each measure. `evals/candidate.sh` is the procedure below as code. Its
header lists every flag and every output line, and
`test/candidate_test.sh` proves it with no model call.

### The rules

1. *Coverage is the limit.* A change can degrade an outcome that nothing
   measures. So the measurements grow before a campaign of changes.
2. *Test on the floor model.* The floor of a slot is the cheapest model on
   which its suite is green. A critic's floor is the model that its
   `opus` alias resolves to. `evals/floors` names the model of each suite, and the procedure
   refuses a run on another one.
3. *A change enters as a reviewed change.* No tool commits here. An accept
   from the procedure is not the release gate. The procedure never reads
   the held-out cases.
4. *A change carries its upgrade path.* A consumer repo holds state that
   hone wrote. That state is the adapters, the policy files, the settings
   block, and the docs shapes. A change to it needs one of three paths:
   - *None needed*, because no consumer state changes.
   - *Mechanical*: `scripts/setup.sh` or a `/hone:garden` pass carries it,
     with a test that starts from the old shape.
   - *Manual*: [`upgrading.md`](upgrading.md) names a step for a person,
     and the step counts as human attention.

   With no path, the procedure rejects. The script sees consumer state
   only under `templates/` and in `scripts/setup.sh`. Pass `--state-change`
   for the rest.
5. *A cheap, deterministic check needs no measured gain.* Cheap means
   three things. It makes no model call. It ships no new tool. It is
   exact. Such a check enters on its own tests, a lab pass with no fail,
   and its upgrade path. A heuristic that can misfire costs human
   attention, so it must show a gain.

Each class of building block has its own evaluator:

- *Prose and judgment* (the skills, the critics, the nag). They make up
  for what a model does not do unprompted, and they expire as models
  improve. The unit suite judges a trim. The lab judges a removal.
- *Safety against the model* (the guards, the deny rules, the land
  gates). Only a lab scenario in which the model reaches for the forbidden
  path measures them. The models that reach are below the floor, so such
  a candidate may run on a model that `evals/floors` lists for it.
- *Coordination* (worktrees, locks, land's merge and re-verify). They
  guard against the environment, not the model. They are out of scope.

### The procedure

A candidate is one uncommitted diff to the shipped plugin, with a brief at
`.plans/<slug>.md` that says which outcome it moves or which price it
lowers. A defect fix is not a candidate. It comes with a test that was red,
and [`releasing.md`](../.claude/rules/releasing.md) alone gates it.

1. Keep a baseline per release. On a clean tree, run each unit target with
   `--votes 3 --json` on its floor. Run each scenario that has a `goals`
   file three times. Every candidate on that base uses these results.
2. Apply the candidate to the working tree.
3. Run `bash evals/candidate.sh plan`. It prints the suites that the
   candidate owes, their cost, the upgrade path, and the size.
4. Make the owed runs. The lab copies the plugin from the tree, so a run
   measures the candidate.
5. Run `bash evals/candidate.sh decide` with both arms.
6. An accepted candidate goes through the release gates. A rejected one is
   reverted, and its brief and numbers go into a note under `docs/spikes/`.

### The verdict

`decide` rejects a candidate for any of these:

- The mechanical suite is red.
- A unit case flips its plurality.
- A lab scenario fails more often than at the baseline.
- A goal measure drops by two runs of three or more.
- A scenario ends in two more distinct ways than at the baseline.
- Consumer state changes with no upgrade path.
- The shipped prose grows and no measured outcome moved up.

The last rule holds for prose alone, because a model executes prose and
prose expires. Every other candidate needs only that every outcome holds.

`decide` answers *undecided* when the evidence is thin, and each line names
the run to make. It also refuses a change to a shipped path that no suite
measures, such as a new skill. The plan skill owes `plan-clear` and
`plan-fork`, and the setup skill owes `setup-misfit`.

Two runs count as one plugin for a scenario when they agree on every
shipped path that the scenario loads. So a baseline that differs only
elsewhere still compares.

A tally that moves by one vote of three is noise. `decide` then asks for
that case at ten votes on both arms. At ten votes a fall of one is noise,
and a fall of two rejects. A rise counts as a gain under the same numbers.

Among accepted candidates the price decides: human attention first, then
dollars and minutes, then the size of the shipped prose and code.

### What an evaluation costs

The figures are API prices from 2026-09-18 on claude-opus-5. The account
is on the Max plan, so the real limit is the plan's usage.

- `plan` and the mechanical suite: no model call, two minutes.
- One unit target at three votes, both arms: 1 to 3 dollars. The whole
  unit suite costs about 4 dollars per arm.
- One case at ten votes, both arms: about 1 dollar.
- One goal scenario, three runs per arm: about 14 dollars and 45 minutes.
  A kept baseline halves that.
- One full lab pass: about 36 dollars and 65 minutes.
- A section ablation: about 9 dollars for the `consolidate-critic` and 25
  for the `plan-critic`.

So a trim of a critic costs about 10 dollars with a kept baseline. A
change to the run skill or to a hook costs about 50 dollars. It owes the
whole lab and three runs of each goal scenario.

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
