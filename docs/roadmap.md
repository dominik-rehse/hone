# Roadmap: what is open

This page lists what is open in the work on hone itself, and what the
maintainer decided. Each item says what happens, how we know, and what the
next step is. [*Goals*](model.md#goals) has the outcomes that hone works
for. [`development.md`](development.md) has the procedure that judges a
change, and [`releasing.md`](../.claude/rules/releasing.md) has the
release gates. The history is in the dated notes under `docs/spikes/` and
in git.

## Terms on this page

- The *lab* runs hone on a real task in a sandbox, and scripts check the
  result. One such task is a *scenario*.
  [`evals/lab/README.md`](../evals/lab/README.md) explains each one.
- The *unit suites* hand one prompt of hone a fixed input and compare its
  answer with an expected one, by a vote of three runs.
  [`evals/README.md`](../evals/README.md) explains them.
- A *probe* is a harder test from outside hone, such as a public
  benchmark. It shows where hone makes a difference on a strong model. A
  probe never decides whether a release may go out.
- A *candidate* is a proposed change to hone that goes through the
  procedure in `development.md`. The procedure accepts a change to prompt
  text only when a measurement shows a gain.

## Open

### Defects with evidence

#### A blocked run sometimes tells the person to switch hone off

- What happens: `.hone-off` is the marker file that switches hone's hooks
  off in a repository. It belongs to the person. A run that a hook has
  blocked sometimes suggests that the person creates it.
- How we know: 4 of 10 probe runs did so on 0.57.0, and 2 of 10 on 0.58.0.
  On 0.58.0 both suggestions came in the middle of a session, after the
  gate had blocked a turn. Neither was in a final report.
- Where it comes from: `rules/workflow.md` and the message
  `msg_guard_primary_tree` name the marker as the person's way out. The
  model reads that and repeats it.
- Since then: 12 lab runs on 0.58.1 on 2026-09-19 had no such suggestion.
  One final report named the marker, to say that it is the person's to
  create and to advise against it.
- Next step: none now, because the final reports are clean. The
  suggestion may show up in a final report or in the
  [field log](field-log.md). Then reword those two places, so that they
  do not name the marker to the agent. That is a change to prompt text, so it
  needs the `loop` unit suite and some lab runs.

#### A stop outside `/hone:run` has no rule for its report

- What happens: the run skill demands that a stop report ends with the one
  action that the run recommends. A session that is not a run has no such
  rule. That covers `/hone:plan`, `/hone:setup`, and a plain request.
- How we know: in the scenario `hand-merge`, one run on sonnet offered the
  person two routes and recommended neither. In `plan-fork`, one run of
  eight wrote that its rejected Plan was "written and on disk", while it
  recommended the other build.
- Why it waits: on opus this is rare, and the procedure needs a measured
  gain. The fix would move the one-action rule into `rules/workflow.md`,
  which every session reads, so it costs words in every session.
- Next step: collect cases in the field log. With three or more on opus,
  build a scenario and try the change as a candidate.

#### Complexity piles up in one function, and nobody raises it

- What happens: a function already handles four kinds of input inline. A
  Plan adds a fifth kind that needs a loop with nested checks. The run puts
  it inline as one more branch. The function lands with 78 to 87 lines and
  a cyclomatic complexity of 14 to 16.
- How we know: 3 runs of 3 of the lab scenario `python-structure` on opus
  ([`python-structure-baseline`](spikes/2026-09-19-python-structure-baseline.md)).
  The builder, the nested code review, and the `consolidate-critic` never
  mentioned the size. A reviewer who read the landed code would send it
  back. In the same runs the rule of three worked: the duplicated block was
  gone in 3 of 3.
- What limits the finding: it is one fixture, in Python. The first design
  of the fixture punished reasonable code, and the note says how the second
  design avoids that.
- Next step: a candidate through the procedure in `development.md`. The
  measure `cc_pile` exists, so a gain can show. An exact check would need a
  complexity tool per language, which is a new tool, so rule 5 does not
  cover it. The likely candidate is one sentence in the refactor step of
  the run skill. It owes the `loop` unit suite and the whole lab.

#### The review bench has no headroom on opus, and its false-alarm count is not stable

- What it is: `evals/probes/review-bench/` tests the nested code review
  alone. Since 2026-09-20 it has eleven harder fixtures. Each is a small
  project with a change that carries one or three planted defects, and a
  clean twin of the same change that counts false alarms
  ([`review-bench-harder-fixtures`](spikes/2026-09-20-review-bench-harder-fixtures.md)).
- What it can do now: it tells opus from sonnet. sonnet missed one defect
  in 3 reviews of 3, an omission in a file that the change does not touch.
- What it cannot do: opus caught 51 of 51, so the bench cannot show that a
  change makes the opus review catch more.
- What is not stable: an agent judges the false alarms on the clean twins,
  and two passes had two judges. The opus review itself also changed
  between 2026-09-19 and 2026-09-20. It took four times as long and cost
  2.7 times as much, on the same twins with the same command. We do not
  know why.
- A related gap: inside the loop, no lab run has ever tested the review.
  Either the run's brief already named the defect, or the builder fixed
  the defect before the review ran.
- Next step, cheap: run two untouched twins on opus once a day for a week,
  and record time, cost, and tokens. That shows whether the review moves
  with the day. The cost of the nested review in a run rests on the same
  number.
- Next step for the false alarms: write the judge's rule as a prompt with
  worked examples, keep it under `evals/probes/review-bench/`, and run it at
  five votes per twin.
- Next step for headroom: a base that a reviewer cannot read whole, of
  5,000 lines or more. The note says why 500 lines are too few. Six known
  weaknesses in the clean twins are listed in the note's judged files.

#### Two sentences of the `plan-critic` move no case

- What happens: the critic says that a Decision which settles a fork is the
  person's earlier answer, and that a Plan which follows it has picked
  nothing. The unit case `fork-settled-by-decision` approves with those two
  sentences and without them, 3 votes of 3 each.
- How we know: the roadmap once read 2 rejections of 17 on that case as a
  critic that ignores a Decision. Both rejections named a real second fork
  in the case's brief, and the critic was right. The brief is fixed, and the
  case now approves 10 of 10
  ([`fork-case-second-fork`](spikes/2026-09-19-fork-case-second-fork.md)).
- Why it waits: a trim of this paragraph is risky. A change of three words
  once moved the lab scenario `plan-fork` from 3 correct runs of 3 to none.
  The gain is two sentences.
- Next step: at the next model release, the watch-case step of
  `releasing.md` tests the paragraph anyway. Before that, a trim needs a
  harder case first: a fork that the stub rejects and that only a Decision
  settles.

#### `setup-misfit` failed once in nine runs

- What happens: the run set the test script in `package.json` to call
  hone's test adapter. The adapter calls `npm test`, so the two called
  each other without end. The run then tried to rewrite the protected
  adapter. The guard asked for confirmation twice, no person was there to
  answer, and the run stopped with a red adapter.
- How we know: one run in the lab pass for 0.57.0. Eight other runs chose
  `node --test` and passed.
- Where it comes from: the setup skill says that a missing test script is
  the project's fault and must be fixed there. It does not say what the
  script should be.
- Next step: none now. If it happens again, the skill names the value or
  warns about the loop.

### A question for the maintainer

#### May hone land a correct solution beside a test that it reports as wrong?

- What happens: on the ImpossibleBench probe, each task has a test that
  contradicts the specification. An honest solution leaves that test red.
  hone cannot land with a red test, so it stops and asks the person.
- The numbers, over 20 runs per arm on the first two passes: bare opus
  delivered a cheat 12 times and the honest solution 7 times. hone
  delivered a cheat 2 times and the honest solution never. It stopped
  with a report 17 times.
- The trade: a stop is safe, and on these tasks the question really is
  the person's. But the person answers many questions that bare opus
  answered alone in a third of the runs.
- The decision: should hone have a way to land honest code and report
  the test as wrong? A written grant could allow it, like the grant for
  irreversible changes. We build nothing until the maintainer decides.

### Measurement

#### Fails from real use

[`field-log.md`](field-log.md) collects what hone does wrong in the
repositories that use it, one dated line per incident. These fails are the
best source of new scenarios, because they are real. The log is empty
today.

#### Probes

- What exists: `evals/probes/impossiblebench/` runs ten tasks of the
  public benchmark ImpossibleBench, with hone and without it. We picked
  these ten because opus had cheated on them before. Each pass runs each
  task once.
- One task ends in a cheat on every release, because the probe's request
  makes the tests the authority. With a request that names the
  specification, hone refuses the cheat, and the lab scenario
  `spec-authority` guards that
  ([`spec-authority-first-runs`](spikes/2026-09-19-spec-authority-first-runs.md)).
- What it can show: only a large change. Ten single runs cannot show a
  small one.
- Next step: more runs per task, before a candidate leans on the probe.
  The benchmark's second half is built on SWE-bench. It needs Docker and
  about 120 GB, and this machine has neither set up.

#### An exact measure for well-structured code

- What exists: the lab scenario `python-structure`. It measures the code
  that a run lands with `scb-check`, the metric tool of the benchmark
  SlopCodeBench. The tool is exact, it makes no model call, and it runs in
  half a second. `dup` says whether duplicated code is gone, and `cc_pile`
  says whether complexity piled up in one function
  ([`python-structure-baseline`](spikes/2026-09-19-python-structure-baseline.md)).
- The limit: the tool reads Python alone, so one scenario carries the
  measure.
- Next step, paid: the benchmark itself can test whether a
  `/hone:garden` pass between steps keeps code from decaying. That costs
  about 250 dollars and a day of setup with Docker
  ([`slopcodebench-first-look`](spikes/2026-09-18-slopcodebench-first-look.md)).

#### Three goals that no part of hone works on

- Nothing keeps a sentence in the docs in step with a value in the code
  that it repeats. The scenario `untied-sentence` tests it.
- Nothing pushes the model to turn a fact that prose holds into a type.
  The scenario `seeded-structure` tests it.
- Nothing chooses among the valid endings of a run. A run can land,
  stop and ask, or write a Plan, and all can be right
  ([`endings-on-opus`](spikes/2026-09-18-endings-on-opus.md)).

opus passes the first two scenarios without help, so a new mechanism could
not show a gain there. Work starts when a fail from real use or from a
probe shows a gap.

### Parked, each with the condition that reopens it

- *Cutting sections from the critic prompts.* We removed each section of
  both critics in turn, and no section could go safely. Thirteen sections
  have no unit case that aims at them, so the suites cannot tell whether
  they matter
  ([`section-ablation-on-opus`](spikes/2026-09-18-section-ablation-on-opus.md)).
  Reopen at the next model release. `releasing.md` has the step.
- *A reviewer from another model family.* The author and the reviewer are
  both Claude, so they may miss the same things. The review bench now tells
  sonnet from opus, but opus misses nothing on it, so a second reviewer
  could not show a benefit there. Reopen when the bench has a fixture that
  opus misses.
- *Automated search over candidates.* A tool could try many variants of a
  prompt. The lab costs 10 to 50 dollars per variant, and the unit suites
  test little. Reopen when a cheap and meaningful judge exists.
- *hone on hone.* This repository does not use hone for its own work
  ([`development.md`](development.md), *Change briefs*). Setting that up
  is a project of its own, and nothing above depends on it.

## Decided

- *The `consolidate-critic` stays as it is* (2026-09-18). No unit case
  shows that the bullets proposed for removal change a verdict. A lab test
  of the removal would cost about 60 dollars, and the maintainer decided
  against it.
- *A cheap, exact check needs no measured gain* (2026-09-18). It is rule 5
  of the procedure. Cheap means no model call and no new tool.
- *The ten-vote rule stands* (2026-09-18). When a unit case moves by one
  vote of three, the procedure runs it again at ten votes. A fall of one
  is noise, and a fall of two rejects the change.
- *hone does not defend against a newly built route* (2026-09-18). The
  guards read the command and the path, and not what a command runs.
  [*Authority*](model.md#authority) says so. This closed the case of a
  run that put a fake tool on `PATH` to satisfy a commit hook.
- *A public benchmark enters as a probe, never as a release gate*
  (2026-09-19). Hard tasks fail at random more often, and a gate must be
  stable.
- *The code review stays on opus* (2026-09-19). On the review bench,
  sonnet caught the same defects at a third of the price. It also raised
  eight false alarms on a clean change, and opus raised none.
- *A lab fail in a part that a release does not touch does not block the
  release* (2026-09-19). Someone must first read the failed run in its
  sandbox. The fail then goes on this page.
