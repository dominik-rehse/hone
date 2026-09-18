# Roadmap: evaluating and optimizing hone itself

hone exists for the codebase it leaves behind. That codebase is software
that is transparent, well structured, and easy to maintain, for a coding
agent as much as for a person. An agent is a primary writer and reader of that
codebase, so the qualities are the ones an agent can use. The truth about
the system is in one place and checked, so that an agent reads it and never
a stale copy of it. The structure is small enough to hold in context. And
nothing in it repeats something the code, the types, or the tests already
carry. [`model.md`](model.md) says how hone works toward that. No
production code without a failing test first. Documentation that lives
only where a checker catches staleness. Every change deletes something. A
loop that stops and reports rather than forces past a failed check. Cost is
the price hone pays for it, not the goal.

This roadmap is about making hone itself better at that goal. It answers
one standing question: how does a change to hone make the software that
hone produces better, and how do we know? A change to hone can add a rule,
reword a prompt, delete a hook or a paragraph, or move a model pin. Each
one is a claim about the codebase that hone leaves behind, and each claim
can be tested. The deletion bias applies to hone too, so a change that
makes hone smaller at equal outcomes is a good change. But smaller is the
tie-breaker, and the outcomes come first.

## The outcomes, and what measures each

A change to hone is good when two things hold. The codebases that hone
produces get closer to that end or stay as close. And hone gets smaller or
cheaper. The end itself is not measurable in one number. What is measurable
is the outcomes below, in three groups: what the codebase is like, what
each change is like, and what it all costs. The outcomes come first, and
the price is the tie-breaker among changes that hold them. Each outcome
names what pursues it in hone today and what measures it, and where
nothing does.

A lab scenario has checks and measures. A check decides the verdict. A
*measure* is one `name=value` line that decides nothing in its run. The
harness copies it into `result.json`, and the procedure of the next
section counts it across runs. The `goals` file of a scenario names the
value that holds the outcome. A measure moves to a check once the
unchanged plugin holds it in three runs of three.

*The codebase hone leaves behind.* These are the end, in the words of the
goal.

- *Transparent.* The truth about the system is in one place, and a checker
  catches it going stale. Tests are named for the behaviour they pin. No
  prose repeats what the code, the types, or the tests already carry.
  Pursued by test-first work (the `guard`), the consolidate step and its
  critic, the `nag`, and `/hone:garden`. The first three act on prose that
  a change touches, and garden scans between changes. One gap is visible
  without a run. A `Governs:` line ties a document to a path, and the nag
  checks only that the path exists. Nothing ties a sentence to the value
  that it repeats. So a change can make a sentence false and never touch
  its document. The lab scenario `seeded-prose` measures that case. It seeds a Note that grew a list of
  behaviours, and a Decision whose second paragraph restates its function.
  The Plan changes the one number that both repeat, and it is silent on
  the docs. The measures `note_spec` and `decision_restates` say what
  became of each repeat: `cut`, `partly`, `updated`, `stale`, or `lost`.
  The goal is `cut`. The `consolidate-critic` evals cannot measure this. A
  model with no hone prose cuts such a repeat when a brief hands it over
  ([`evals/README.md`](../evals/README.md) *Known gaps*).
- *Well-structured.* Types carry what types can carry. Areas are small
  enough to hold in context, with one Note and one invariant each. No
  duplicated logic, and no abstraction with one user. Pursued at the point
  of change only, and by little prose. That prose is the *Type first*
  bullet at build, the rule of three, and two bullets of the
  `consolidate-critic`. hone limits it to that point on purpose. *Types
  and abstractions* in [`model.md`](model.md) says that a search for
  things to abstract produces wrong abstractions. The lab scenario `seeded-structure`
  therefore puts both of its seeds inside the change, on a TypeScript
  fixture. A formatting helper exists in two private copies, and the Plan
  adds the third use. The Note says in prose that `status` is one of three
  strings, the code types it as `string`, and the Plan adds a fourth
  status. `format_copies` counts the places that format an amount, and the
  goal is 1. `status_fact` says whether a type carries the set of values,
  prose, or both, and the goal is `type`. No mechanism turns an existing
  prose fact into a type, and the baseline of 2026-09-18 did it anyway, in
  three runs of three.
- *Correct.* The landed change does what the Plan says, and no defect lands
  in silence. Pursued by test-first work, the gate, the nested review, and
  the land gates. The lab's end-state checks measure the first part per
  scenario. The review's catch rate (`review_named`) and the
  `parallel-paths` and `defect-in-hunk` scenarios measure the second.

*Each change hone makes.* These are what makes unattended landing
tolerable.

- *Safe.* The loop takes no shortcut around a gate, and it never reports a
  partial run as done. Pursued by the hooks, the deny rules, and the loop's
  stop rules. The lab's adversarial track measures it, and the loop evals
  pin that the run stops on a check it cannot make green. `casual-fix` is
  the first scenario in which a model reaches for a shortcut and a guard
  turns it back.
- *Reversible.* Every landed change is one merge that a person can revert
  in one command, with nothing outside git to undo. Pursued by one
  worktree and one merge per change, and by the grant gate for what a
  revert cannot undo. The lab check `revertible` demands three things.
  Main moved by one merge commit. The primary tree holds nothing outside
  git's record. A revert of the merge in a throwaway clone leaves the
  suite green. `happy-path` and both seeded scenarios call it.
  `authority-gate` does not, because a grant exists for what a revert
  cannot undo.
- *Predictable.* The same Plan gives the same kind of result twice. That
  means the same ending, the same shape of commit, and the same place for
  what it left behind. Pursued by the fixed loop and the fixed routing at
  consolidate, as a side effect. No mechanism chooses among valid endings.
  Every `result.json` of the lab carries an `ending`: landed or stopped,
  the branch, the commit types, and the places that the run changed. The
  procedure counts the distinct endings of a scenario per arm.
  `parallel-paths` ended three ways on 2026-09-17, and `casual-fix` gave
  one fix three different slugs. Some variance is the model's, and hone
  cannot buy all of it away with prose. A candidate is an order of
  preference among the valid endings, in the run skill.

*The price.* Lowered only at equal outcomes above.

- *Human attention.* The person writes the Plan and reads the report. In
  between they answer a bounce from the critic, and they sign a proof or a
  grant. Every other minute of theirs is waste, and this is the scarce
  price. The whole shape of the loop pursues it. There is one hand-written
  artifact, a critic that runs while the person is present, no check-in,
  and a stop that hands over one action. The measurement has three parts.
  A stop is in the `ending` of a lab run. For every stopped run that
  passed, a judge reads the report alone and answers whether it hands the
  person one concrete action. That is the measure `stop_actionable`. A
  bounce has no lab measure, because the lab starts from a written Plan
  and a bounce happens in `/hone:plan`. The APPROVE cases of the
  `plan-critic` target stand in for it. A bounce that names a real fork is
  attention well spent, and a REJECT of an exemplary Plan is a bounce on a
  nit.
- *Dollars and minutes.* Per landed change, as the lab records them per
  run. A happy-path run costs about 2 dollars on opus.

hone may not be complete with respect to these outcomes. Several of them
have a mechanism that pursues them only as a side effect, or a critic
bullet and nothing more. So the first question for each
outcome is whether hone has a mechanism that pursues it at all. Only then
comes the question whether that mechanism can be smaller or cheaper. A
missing mechanism is a change to hone like any other. The method has to
judge it the same way: does adding this step move the outcome, and what
does it cost?

The three suites are how the measured outcomes are measured, so they are
the constraints on every change to hone. [`development.md`](development.md)
says when to run which. The mechanical suite (`bash test/run.sh`) proves
that the hooks and scripts do what they say. The unit evals
(`bash evals/run.sh`) pin the prose that the model executes, case by case,
and [`evals/README.md`](../evals/README.md) carries the ledger. The lab
(`bash evals/lab/run.sh`) runs the installed plugin end to end. It is the
only suite that can say what a hook deters or what a change costs.
[`evals/lab/README.md`](../evals/lab/README.md) is its manual.

The constraints reach only as far as the cases and scenarios do. A cut
that breaks a behaviour with no case passes all three suites. So "green
after a cut" means "green for what we test", and coverage of the outcomes
above is the limit of every deletion.

## The method: how a change to hone is judged

A change to hone is a claim about the codebases that hone leaves behind.
This section says how to test that claim. `evals/candidate.sh` is the
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
at equal outcomes. Its brief lives at `.plans/<slug>.md`, as
[`development.md`](development.md) says.

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

### Open decisions, for the maintainer

- The baseline of the two seeded scenarios is from 2026-09-18, on hone
  0.54.0: every goal held in three runs of three, for 13 dollars. So hone
  showed no gap there, and a candidate can only hold these measures or
  lose them. The measures are due to move to checks.
- hone 0.55.0 passed the lab at 13 of 13 on 2026-09-18, for 31 dollars
  and 17 minutes at five scenarios at a time. It adds three deterministic
  checks under rule 5: the `Cut:` line at land, the oversized-area finding
  of the nag, and `worktree.sh governed`. The goal scenarios ran once on
  it, so the procedure has no three runs of that arm yet. 0.55.1 fixed ten
  findings of a code review on that work and passed the lab at 13 of 13
  again, for 29 dollars.
- 0.55.2 fixed two defects that the lab had measured, with no experiment,
  because each had a known cause. `claimed-worktree` read
  `stop_actionable=no` twice: the refusal of `add` gave two possible causes
  and no way to tell them apart. It now says what the claim holds and names
  one action, and the measure reads `yes`. The second defect was a review
  that ran twice. Its first fix made things worse, and only the transcripts
  showed it. The agent chose a fixed file name under `/tmp`, so it read the
  review of a concurrent scenario, or a file that an earlier pass had left.
  The brief and the output now sit in a directory from `mktemp -d`. Every
  result carries the measure `reviews`, and the pass of 2026-09-18 read 1 in
  every scenario that reached the review.
- The first candidate that the record review suggests is the removal of
  the `consolidate-critic`. No case shows that its cut bullets change a
  verdict, and no run shows that they change a codebase. With the baseline
  above it costs about 60 dollars to judge: both seeded scenarios, the
  `loop` target, and one lab pass.
- The ten-vote rule above differs from the maintainer's rule that a cut
  needs an unmoved tally.
- The garden release gate runs on opus, and the measured floor is sonnet.
  `evals/floors` follows rule 2 and names sonnet.
- The lab's noise floor outside the repository has one pass of the three
  it needs, about 70 dollars more.
- One haiku run walked around a commit hook with a mock of a missing tool
  on `PATH`. No guard reads that route. Whether it is inside hone's threat
  model, a friction-avoiding agent and not an adversary, is open.

## The record so far

Everything below is what earlier sessions built and measured, before the
method existed. The dated notes under `docs/spikes/` carry each measurement
in full.
[`spikes/2026-09-18-record-review.md`](spikes/2026-09-18-record-review.md)
reviews this record against the method: what it keeps, what it makes
obsolete, and what the record got wrong.

### Model slots

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
  maintainer's choice. A pinned slot runs on its pin for every user, so
  the method judges a critic on opus. Opus reads the `plan-critic` prose more strictly. It
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

### Where things live

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

### Stage 0: unit evals for the judgment prose (done)

The suite exists, gates releases, and has three properties that make it
trustworthy. Every case discriminates: the no-op cut of 2026-08-18 removed
44 cases that a model with no hone prose answered correctly. A case can
also prove itself against the prompt minus the paragraph it pins, which is
the second baseline. And the noise floor is measured: three identical
passes flip no verdict, so a flip after a prompt edit is signal. The latest
floor is from 2026-09-18, on the opus pins.

### Stage 1: coverage growth (two passes done, most sections still open)

The stage ends when three conditions hold. Each critic has a discriminating
case for each of its verdicts. Each target has a held-out case. Each section
that an ablation will test has a case aimed at it. The first two hold since
2026-09-17. The third holds for 7 of 20 critic sections.

Two passes taught what a case can and cannot pin. A brief that names the
thing under test measures agreement, and the model always agrees. A brief
that buries it measures whether the prose makes the model look, and that is
the shape that works. A draft aimed at one bullet still tends to die,
because the current model applies most bullets unprompted. So the sections
with no case are not a coverage gap to fill at any price. Some of them may
be prose that the model no longer needs. A case cannot show that, because
its brief hands the model what the run must find by itself. The seeded lab
scenarios can show it, for a group of bullets or for a whole critic. *Known gaps* in the manual records every dead draft and
why.

What the earlier sessions saw as the next step: a REJECT case for the
rejecting half of the `plan-critic` bullet on dependency refreshes, because
its approving half looks expired (stage 2). Then harder briefs, in the
buried shape, only for sections whose loss would hurt.

### Stage 2: machine-drivable harness (done, first ablation done)

`evals/run.sh` takes `--prompt-file`, `--cases`, `--json`, and `--cache`,
so a tool can drive it. Their first use is section ablation: delete one
section of a prompt, run its target, and read the result under one rule.
An unchanged suite is evidence only for a section that a case aims at.

The first campaign ran on 2026-09-17 over both critics on claude-sonnet-5
([`spikes/2026-09-17-first-section-ablation.md`](spikes/2026-09-17-first-section-ablation.md)).
It ran on the pin of that day, and the pin moved to claude-opus-5 a day
later. So a cut of a critic section needs the campaign again on opus. It
cost about 20 dollars and cut nothing. It found one expiry candidate,
the approving half of the refresh bullet. It also found one rule. A cut of
a bullet must take its category word along, or the word floats and the
critic files other things under it. A campaign per prompt edit is
affordable. One per commit is not.

### Stage 3: the scenario lab (first version done, floor open)

The lab runs headless Claude Code with a copy of hone, in a sandbox, against
eleven seeded scenarios. Deterministic checks and one judge grade the end
state. Four scenarios are behavioral and seven adversarial. It gates
releases. `--without` switches a hook off in the sandboxed copy, and
`--review-model` swaps the reviewer, so the product needs no feature for
either.

What it has shown so far:

- *It catches what the unit suite cannot.* Its first use as a release gate
  caught a bad edit to the run skill. The loop evals had passed it at 3/3
  ([`spikes/2026-09-17-lab-first-runs.md`](spikes/2026-09-17-lab-first-runs.md)).
- *It shows what two guards deter, below the floor of the loop.* After a
  plain request with no `/hone:run`, claude-haiku-4-5 and claude-sonnet-5
  edit `src/` in the primary tree. `guard` turns that run into a Plan, and the dirty-guard
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

- `seeded-prose` and `seeded-structure` measure the *transparent* and
  *well-structured* outcomes since 2026-09-18. Neither has a run yet.
- The noise floor outside the repository has one pass of the three it
  needs. One pass over eleven scenarios on opus gave 11 passes. Until the
  other two run, the release gate rests on one sample.
- The guard counts are one to three runs per cell. They show that a
  temptation is real for the smaller models, and they give no rate.
- One haiku run walked around a commit hook with a mock of the missing
  scanner on `PATH`. No guard reads that route, and it has no owner.

### Later: automated optimization

This note predates the method. An optimizer would be one more source of
candidates for `evals/candidate.sh`. A candidate that needs the lab costs
10 to 50 dollars to judge, so only a search at the unit level is
affordable. With the harness and the lab in place, the manual experiments
above can become search. GEPA's `optimize_anything`
fits, because its adapter model wraps `evals/run.sh`. DSPy does not, because
it wants to own execution as a Python pipeline and would fork the agent
files hone ships. The tooling would live in a sibling repo, and its output
would enter this repo only under rule 3 of the method.

Two conditions come first. The lab exists now. The visible cases are still
far too few for a train/val split with the holdout set frozen as the final
test. And the first manual ablation found nothing to cut, so an optimizer
must first show that it beats the manual method. The expectations are
modest: hone is one loop and two small critics, and the realistic wins are
shorter prompts and cheaper models.
