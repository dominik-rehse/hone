# Developing hone

This page is for changing the plugin itself. [`model.md`](model.md) (why it
works this way) and [`reference.md`](reference.md) (the control surface)
cover using hone in a project. [`roadmap.md`](roadmap.md) has the outcomes
that hone is judged by, and the open items.

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
calls. It covers the hook unit tests, the end-to-end land path (worktree,
gates, merge, rollback), the plumbing of the eval harness and of the
scenario lab against a fake CLI, the candidate procedure against
hand-written results, and two checks over the message templates. Every
message hone prints lives in `hooks/messages.sh`, and the checks lint its
prose and hold it to the shape. Run this suite after any change to
`hooks/`, `scripts/`, `evals/run.sh`, `evals/candidate.sh`, or `evals/lab/`.
The shell sources also stay `shellcheck`-clean
(`.shellcheckrc` sets the dialect). Nothing runs shellcheck for you, so
run it over any script you touch.

*Judgment*: `bash evals/run.sh`. This suite calls models. It pins the
critic prompts and the run skill's loop instructions to cases with
known-good answers. [`evals/README.md`](../evals/README.md) is the manual:
targets and cases, the balance between reject and near-miss pass cases,
plurality voting, and the held-out set discipline. Two rules matter most.
Match the model to what runs in production. The critic frontmatter pins a
full model ID, and the harness defaults to it. The loop and garden targets
run with `--model opus`. And never read or
tune against a `*-holdout` case while editing prose.

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
[`roadmap.md`](roadmap.md) names the outcomes that such a claim is about,
and what measures each. This section says how to test the claim. `evals/candidate.sh` is the
procedure as code, and its header lists every flag.
`test/candidate_test.sh` proves it with no model call.

### The rules

1. Eval coverage sets the limit of every change. A change can degrade an
   outcome that no case and no scenario measures. So the measurements grow
   before any campaign of changes.
2. Test every change on the *floor* model, not the best one. A slot that
   runs on the session's model has a floor: the cheapest model on which its
   suite is green. A change that holds on the best model can break a user
   on a cheaper one. A slot that hone pins runs on its pin for every user,
   so its floor is the pin. `evals/floors` has the model of each suite, and
   the procedure refuses a run on another one.
3. A change enters this repo as an ordinary reviewed change, through the
   eval gates and a version bump like any prompt edit. No tool commits
   here. An accept from the procedure is not the release gate. The held-out
   cases stay out of the procedure, because a campaign that reads them
   tunes against them.
4. A change to hone carries the way for a downstream repository on an
   older version to take it. hone is a distributed plugin, and the repos
   that use it hold state that hone wrote. That state is the adapters
   under `scripts/`, the policy files, the settings block, and the docs in
   the shapes hone prescribes. A change that alters any of that is
   complete only with its upgrade path. *The upgrade path* below says how
   the procedure judges it.

5. Where a cheap, deterministic check can enforce a principle of hone,
   hone uses it. [`model.md`](model.md) *Checking* already says so for the
   loop: prefer the mechanical kind wherever the question is computable.
   The same holds for a change to hone. Such a check needs no measured
   gain. It enters on the constraints alone: its own tests in `test/`,
   the lab with no fail, no outcome that drops, and its upgrade path.
   Three conditions make a check cheap. It makes no model call. It ships
   no new tool, so a project supplies any tool through an adapter. And it
   is exact. A heuristic that can misfire spends human attention on every
   false alarm, so it must show its gain like prose.

Each class of building block has its own evaluator. A change to one class,
tested with the evaluator of another, measures nothing:

- *Model-compensating prose and judgment* (skill instructions, the critics,
  the nag). They exist because models at writing time did not supply the
  behaviour unprompted, and they expire as models improve. The unit suite
  evaluates trims within them. The lab evaluates removing them whole.
- *Mechanical safety against the model* (guard, bash-guard, the settings
  deny rules, the land gates). They defend against rare misbehaviour, so
  average-case evals under-measure them by construction. Only the lab's
  adversarial scenarios can measure their value. Even there, only a
  scenario in which a current model reaches for the forbidden path counts.
  The models that reach are the ones below the floor of the loop, so rule
  2 has one exception here. A candidate that touches a guard may run both
  arms on a model below the floor, and `evals/floors` lists those models.
  Their deletion bar is higher anyway. They are deterministic and nearly
  free when not triggered. They are also part of what makes a human
  willing to leave a run unattended.
- *Mechanical coordination* (worktrees, locks, land's merge-and-reverify).
  They guard against the environment, not the model, so better models never
  obsolete them. Out of scope. Only a workflow redesign would remove one.

### What a candidate is

A candidate is one diff to the shipped plugin, in the working tree, against
a base commit. Two things come with it. The first is its upgrade path. The
second is a claim: the outcome that it moves, or the price that it lowers
at equal outcomes. Its brief lives at `.plans/<slug>.md`, as *Change
briefs* below says.

Candidates come from five places:

- A section of prompt prose deleted. *Section ablation* in
  [`evals/README.md`](../evals/README.md) says how.
- A hook switched off with `--without`, or a critic deleted in the tree.
- A model pin moved. [`releasing.md`](../.claude/rules/releasing.md) has
  the steps.
- A new step or a new rule. It answers a measure that the baseline does
  not hold, or a misjudgment in real use that a new case captured.
- A new model release. It makes every section a candidate again, in both
  directions. Downward: does the existing prose still hold? Upward: which
  prose is now unnecessary?

The procedure treats an addition and a cut alike. It asks whether the
outcomes moved and what the change costs. One rule differs. A candidate
that grows the shipped prose is accepted only when a measured outcome
moved up. Prose is what a model reads and executes, and it expires as
models improve. Every other candidate is accepted when every outcome
holds. That includes a deterministic check that grows the shipped code
(rule 5).

The procedure judges optimization candidates. A defect fix comes with a
test that was red before it, and
[`releasing.md`](../.claude/rules/releasing.md) alone gates it.

### The procedure

1. Keep a baseline per release. On a clean tree, run each unit target with
   `--votes 3 --json` on its floor. Run each scenario that has a `goals`
   file three times. Keep the files and the run directories. Every
   candidate on that base uses them again.
2. Write the brief and apply the candidate to the working tree. Do not
   commit it.
3. Run `bash evals/candidate.sh plan`. It prints the suites that the
   candidate owes, what they cost, its upgrade path, and its size.
4. Make the owed runs with the candidate in the tree. The lab copies the
   plugin from the tree, so a run measures the candidate.
5. Run `bash evals/candidate.sh decide` with both arms. It prints one line
   per finding and then the verdict.
6. An accepted candidate goes through the release gates of
   [`releasing.md`](../.claude/rules/releasing.md). A rejected one is
   reverted, and its brief and its numbers go into a dated note under
   `docs/spikes/`.

`decide` rejects a candidate for any of these:

- The mechanical suite is red, a unit case flips its plurality, or a lab
  scenario fails more often than at the baseline.
- A goal measure drops by two runs of three or more.
- A scenario ends in two more distinct ways than at the baseline.
- The candidate alters consumer state and carries no upgrade path.
- The candidate grows the shipped prose and no measured outcome moved up.

`decide` answers *undecided* when the evidence is thin, and each line names
the run to make. Examples are an indeterminate run, a goal measure with
fewer than three runs per arm, and a run on a model other than the floor.
It also refuses two arms that measured the same plugin. And it refuses a
change to `skills/plan/` or `skills/setup/`, because no suite measures
them.

Among accepted candidates the price decides. Human attention comes first,
then dollars and minutes per landed change, then the size of the shipped
prose and code in words. A manual upgrade step counts as human attention,
once per consumer repository.

### A tally that moves without a flip

On an unchanged prompt, single votes dissent. The noise floors saw 5
dissenting votes of 171 on 2026-09-17 and 1 of 216 on 2026-09-18. So at
three votes a tally that moves by one vote is no evidence, in either
direction. The procedure answers *undecided* and asks for that case at ten
votes on both arms, which costs about one dollar. At ten votes a fall of
one vote is noise, and a fall of two or more rejects. A rise counts as a
gain under the same numbers.

The same numbers decide a cut. A rule that keeps a section whenever a
tally moves reads one vote as signal. A paragraph that moves a case by
exactly one vote of ten stays, and its brief becomes a watch case.

### The upgrade path

`plan` and `decide` rank the path of a candidate:

- *None needed.* The candidate changes nothing that hone leaves in a
  consumer repository.
- *Mechanical.* `scripts/setup.sh` or a `/hone:garden` pass carries the
  change. That is a change to a script or a skill, so it owes its own
  suite, with a test that starts from the old shape.
- *Manual.* [`upgrading.md`](upgrading.md) names a step for a person. The
  candidate is accepted, and the step counts in its price.
- *Missing.* The candidate is rejected.

The script sees a change to consumer state by itself only under
`templates/` and in `scripts/setup.sh`. A new shape of a document under
`docs/`, or a new policy file, shows in no path. Pass `--state-change` for
those.

### What an evaluation costs

Every figure is an API-equivalent from 2026-09-18 on claude-opus-5. The
account is on the Max plan, so the real limit is the plan's usage.

- `plan`, and the mechanical suite: no model call. The suite takes two
  minutes.
- One unit target at three votes, both arms: 1 to 3 dollars. The whole
  suite costs about 4 dollars per arm.
- One case at ten votes, both arms: about 1 dollar.
- One goal scenario, three runs per arm: about 17 dollars and 45 minutes.
  With a kept baseline it is half of that.
- One full lab pass over thirteen scenarios: about 36 dollars and 65
  minutes.
- A section ablation of one critic: about 10 dollars.

So a trim of a critic costs about 10 dollars per candidate with a kept
baseline. A change to the run skill or to a hook costs about 50 dollars.
It owes the whole lab and three runs of each goal scenario.

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
