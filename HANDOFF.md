# Handoff: an environment that optimizes hone

This file hands a program of work to the next agent. You can read it cold.
It assumes no earlier conversation. It was written on 2026-09-20.
[*Status*](#status) says what is done and what runs.

It is a program of several changes, not one change. Before you start a
step, write its brief at `.plans/optenv-<step>.md`, in the shape that
[`docs/development.md`](docs/development.md) describes under *Change
briefs*. Read `.claude/rules/working-here.md` and
`.claude/rules/releasing.md` first. They hold the standing rules of this
repository. Delete this file when the last step is done or dropped.

## Status

Keep this section true. Update it in the commit that finishes or drops a
step. A finished step keeps one line here, with the note or the script
that holds its result.

As of 2026-09-20:

- Step 1 is done (`docs/spikes/2026-09-20-plugin-eval-spike.md`).
  `claude plugin eval` runs hone with every hook on, and
  `context.history_file` resumes a recorded session. The nested
  `/code-review` cannot finish there, because no nested `claude -p`
  reaches the API from the runner's sandbox. The note lists three
  conditions of this machine that refuse a run before any model call.
- Step 2 is in work. Done: the field log, and the hook table that step 5
  needs (`docs/spikes/2026-09-20-field-data-from-real-sessions.md`). The
  raw findings stay under `/var/tmp/hone-fieldlog/`. Ambig-SWE is measured
  and dropped, because it matches hone's notion of a fork poorly. Eleven
  misjudgments of the critics became ten redacted cases
  (`docs/spikes/2026-09-20-cases-from-field-misjudgments.md`). Five went
  into the suites. Two that the shipped prompts fail are under
  `evals/optimize/cases/` as training signal. Three pinned nothing and
  went. All eleven misjudgments happened on claude-sonnet-5, and five of
  the ten shapes do not reproduce on claude-opus-5. In work: data for the
  `plan-critic` from real briefs and from generated defects.
- Step 3 is done. `evals/optimize/sections.py` is the splitter, and its
  header has the rules and the usage. `--fine` gives the finer split for
  the critics. `test/optimize_test.sh` proves the round trip in both modes.
- Step 4: the bare arm is done. `evals/lab/run.sh --bare` runs a scenario
  with no hone, and `evals/lab/README.md` explains it. 17 of 21 scenarios
  can run bare. The harder scenarios are not started.
- Steps 5 to 9 are not started.

## What

Build an environment that can search for better versions of hone by
itself, and that reports the trade-offs between hone's goals as a Pareto
front. A Pareto front is the set of versions where no other version is
better on every goal at once. The maintainer then picks one version from
the front, and it ships through the release gates that exist today.

The search has two layers:

- *Structure.* Which parts does hone need at all? The parts are the
  hooks, the two critics, the steps of the loop, the nested review, and
  the land gates. The question is whether every check earns its cost.
  This layer is a small set of switches, so it is searched by switching
  parts off and measuring. [*The structure layer*](#the-structure-layer)
  has the method.
- *Text.* Inside a fixed structure, which wording is best? GEPA
  (<https://gepa-ai.github.io/gepa/>) is the search tool. GEPA runs a
  candidate text on examples, lets a model read the traces of the failures,
  and lets it rewrite one part of the text. It keeps the versions that no
  other version beats.

Structure comes first. There is no point in tuning the words of a step
that the structure layer then removes.

## Why

The work of 2026-09-17 to 2026-09-20 built a release gate: unit suites, the
lab, two probes, and `evals/candidate.sh`. A gate says whether one change
is safe. It cannot search. A review of that week found these limits:

- *No headroom on opus.* GEPA learns from failures. hone passes nearly all
  of its own cases on claude-opus-5. The review bench caught 51 of 51. On
  2026-09-18 opus passed six of the seven adversarial lab scenarios of
  that day with the guards off
  (`docs/spikes/2026-09-18-impossiblebench-first-look.md`). The track has
  ten scenarios now, and nobody has run the three new ones that way.
- *No evaluator at a middle price.* A unit call costs about 2 cents. For
  the skills it tests the wrong setting. The text sits in the system
  slot, and in real use it arrives in the middle of a session. A lab run
  costs about 2 dollars and takes minutes. A GEPA run needs 100 to 500
  runs, so the lab alone would cost 200 to 1,000 dollars per search.
- *Too few cases.* 21 lab scenarios and 33 unit cases. A search over
  so few cases writes the cases into the prompt.
- *The prose never shrinks.* Two ablation campaigns cut nothing. The
  reason is that 13 sections have no case that aims at them, and the rule
  says such a section stays. The shipped prose is about 19,000 words.
- *No data from real use.* `docs/field-log.md` is empty. About 220 session
  transcripts from the four consumer repos sit under
  `~/.claude/projects/-home-dominik-repos-<repo>/`.

## The design

### What GEPA needs from us

Checked against the GEPA docs on 2026-09-20:

- A candidate is a dict from a component name to its text.
- An adapter has two methods. `evaluate(batch, candidate, capture_traces)`
  returns one score per example, the outputs, the traces, and an optional
  `objective_scores` dict per example. `make_reflective_dataset` turns the
  traces into feedback for the model that rewrites.
- `gepa.optimize(..., frontier_type='objective')` keeps a front per
  objective. The default keeps one per validation example.
- Other parameters we need: `max_metric_calls` for the budget, `run_dir`
  to resume, `cache_evaluation`, `reflection_minibatch_size` (default 3),
  `reflection_prompt_template`, and `module_selector='round_robin'`.

### Components are sections, not files

One component is one section of a skill or a critic, split at its headings.
A script splits a file into sections and joins them again. So each rewrite
touches one section, and a deleted section is visible as such. A whole
skill of 4,700 words is too large to rewrite in one step.

A critic needs a finer split. The `plan-critic` has two headings, and its
named units are the bullets under *What to hunt* and the *Calibration*
paragraph. The locks of step 6 name those units. So the splitter has a
fine mode for the critics, and the skills keep the split at headings.

### The goals, and how the search treats each

[*Goals*](docs/model.md#goals) names eight: six outcomes, and a price of
two parts. It also gives the rule: hone lowers the price only when the six
outcomes hold. The search keeps that rule. An *axis* is a goal that the
front spreads over. A *condition* is a goal that a version must hold to be
on the front at all.

| Goal | Today | Measured by |
| --- | --- | --- |
| Transparent | condition, axis after step 4 | `note_spec`, `decision_restates`, `docs_true` |
| Well structured | axis on `cc_pile`, wider after step 4 | `format_copies`, `status_fact`, `dup`, `cc_pile` |
| Correct | axis | the lab verdict, or the critic's verdict |
| Safe | axis | `reached`, and the adversarial checks |
| Reversible | condition | the lab check `revertible` |
| Predictable | condition | the count of distinct `ending` lines per scenario |
| Human attention | axis | `bounced`, `stop_actionable`, stops and asks |
| Dollars and minutes | axis | cost and time in each `result.json` |

`evals/lab/README.md` explains each measure. Each axis becomes a score
between 0 and 1 per run, and cost and time are scaled against the shipped
version. `attention` counts a stop or a question only where none was due. A
correct stop costs nothing.

Why *transparent* is a condition for now: it has two lab scenarios, and
opus passes them. An axis on which every version scores the same spreads
no front. Step 4 builds the scenarios that give it room, and then it
becomes an axis.

*Well structured* has room already, in one place. Of its three scenarios,
opus passes `seeded-structure`, and it holds `dup` of `python-structure`.
It fails `cc_pile` there in 3 runs of 3
(`docs/spikes/2026-09-19-python-structure-baseline.md`), and the roadmap
lists that as an open defect. So `cc_pile` is an axis from the start. It
is one fixture in one language, and step 4 widens it.

Why two outcomes stay conditions: *reversible* and *predictable* are
properties that a version has or lacks. Nobody wants to trade some of
either for a lower price. `evals/candidate.sh decide` treats them so
today: a run that is not `revertible` fails, and two more distinct endings
than the baseline reject.

One axis is not a goal of hone: `words`, the size of the shipped prose. It
stands for the context that every session pays and for prose that expires
as models improve. `docs/development.md` ranks it last among the prices,
and so does the search.

Be honest about what the first fronts will show. As long as opus is at
the ceiling on the outcomes, a front is "all outcomes hold, and the price
varies". That is useful, and it is less than a front across the goals.
Step 4 is what widens it.

### The structure layer

hone has these parts that can be switched:

- the hooks: `guard`, `bash-guard`, `dirty-guard`, `gate`, `nag`, and
  `session-start`, which injects `rules/workflow.md`
- the agents: `plan-critic` and `consolidate-critic`
- the steps of the loop in `skills/run/SKILL.md`: the test-first build,
  verify, consolidate, the nested `/code-review`, and land
- the gates inside land: the proof gate, the grant gate, and the shape
  gate that demands a `Cut:` line
- a setting per part: the model of each critic, and the model and the
  level of the review

A *variant* is a list of parts that are off, plus the settings. One script
builds a copy of the plugin from a variant. `evals/lab/run.sh --without`
does this for hooks today. For a step or an agent, the script removes the
sections that call it, with the splitter of step 3. So one manifest format
describes a structural variant and a text variant alike.

The space is small, so no search tool is needed at first:

1. Run the bare arm, with no hone at all. It is the zero point of every
   goal. No lab pass has it today.
2. Switch one part off at a time, and run the scenarios that the part is
   meant for, several runs per arm. That gives a table: what each part
   buys on each goal, and what it costs in dollars, minutes, words, and
   human attention.
3. Switch off together all parts that bought nothing, and run the whole
   lab on that lean variant.
4. The front over structures is then a handful of variants: full, lean,
   bare, and what lies between.

Start with the parts that cost the most. The hooks make no model call, so
they cost almost nothing per run. The critics, the consolidate step, and
the review call a model. The review alone is about 12 percent of a run.

One trap needs a rule. A guard is insurance. It shows its value only when
the model reaches for what it forbids, and claude-opus-5 rarely reaches
(see *Why*). So a
lab on opus will say that the guards buy nothing. That is not evidence
that they can go. Judge a guard on three things together:

- the reach rate on the models below the floor in `evals/floors`
- how often the hook fired in the 220 real sessions, and whether each
  block was right or a false alarm
- what it costs when it is wrong, which is human attention

A guard that costs little and gives no false alarm stays, whatever opus
does in the lab. The maintainer said so on 2026-09-20. A cheap guard that
protects quality is fine. It does not have to prove its worth in the lab.
A guard with false alarms must show a reach that it stopped.

### Three tiers of evaluator

1. *Single calls*, estimated at 2 cents each. On 2026-09-20 a call of the
   `plan-critic` on claude-opus-5 measured about 13 cents. Right for the critics, because a
   critic really is a system prompt plus one brief. `evals/run.sh` with
   `--prompt-file --json --cache --cases` already does this.
2. *Decision points*, an estimated 10 to 30 cents each. A recorded session
   resumes just before a decision, and the case grades the next action.
   `claude plugin eval` offers this through `context.history_file`. The
   transcripts of lab runs supply the sessions.
3. *The full lab*, about 2 dollars per run. Only for checking the few
   versions on the front that might ship.

### What `claude plugin eval` is

Anthropic's eval runner for plugins, documented at
<https://code.claude.com/docs/en/plugin-evals>. The CLI has it since
2.1.198. A case is a directory
with a `prompt.md`, graders under `graders/`, and an optional `case.yaml`.
Each run is a fresh headless session with a throwaway home and only the
plugin under test. By default it runs each case with and without the
plugin and reports the difference. It has `--json`, `--runs`, `-j`,
`--max-cost-usd`, `--model`, `--judge-model`, `--eval-dir`, `--keep-temp`,
and `--ablation none`. Graders are `regex`, `tool_used`, `tool_order`,
`file_exists`, `llm`, and `baseline`. It has no grader that runs a script,
so the `check.sh` files of the lab cannot move into it as they are.

Four flags matter for hone. Always pass `--no-publish`: by default the CLI
uploads its HTML report, with the prompts and the verdicts, to claude.ai,
and `.claude/rules/working-here.md` forbids that. A scaffold script runs
only with `--scaffold`. `Bash` needs `--allow-tools Bash`. `--trust-plugin`
answers the trust question of a first run.

## Steps

Do the steps in order. What depends on what:

- Step 4 starts with the bare arm of the lab, which step 5 also uses.
- Step 5 needs the splitter of step 3 and the hook table of step 2.
- Step 6 needs steps 2 and 3.
- Step 7 needs step 1.
- Step 8 needs steps 5 and 7.

So steps 1, 2, 3, and the bare arm can start at once.

Harder scenarios come before the structure and before the big search. On
the scenarios of today claude-opus-5 passes nearly everything. So every
part of hone would seem to buy nothing, and every goal but the price
would stay flat.

### 1. Spike: can `claude plugin eval` run hone?

Write three cases in `evals-spike/` at the root of this repository, and
pass `--eval-dir evals-spike`. The flag takes a directory name below the
plugin, so a directory outside the repository finds no case. The CLI
writes to `evals-spike/results/`. Keep the whole directory untracked, and
delete it when the note is written. The three cases:

- the lab scenario `happy-path`, with `Bash` granted and its `seed.sh` as
  the scaffold script
- the lab scenario `plan-fork`, graded by one `llm` grader on the report.
  The lab's own check asks whether a commit on `main` touches `.plans`. A
  `file_exists` grader reads the working tree, so it would fail a run
  that leaves a draft and commits nothing. Try whether a `regex` grader
  on the trace can see the commit
- one `plan-critic` unit case, called through the `Agent` tool

Answer these questions and nothing more:

- Do hone's hooks fire in a run?
- Does the nested `/code-review` finish? The lab had to hold stdin open,
  because `claude -p` kills background tasks when the turn ends.
- Does a full `/hone:run` end inside the limit of 3,600 seconds?
- Does `context.history_file` resume a recorded session with the hooks on?
- Does the JSON carry the cost of each run and the verdict of each grader?
- Does `--keep-temp` keep the workspace, so that a `check.sh` can grade it
  afterwards?
- Does the `path` of a `file_exists` grader take a glob?

Done when a dated note under `docs/spikes/` has the seven answers.

### 2. Get labeled data for the `plan-critic`

- Check the release and the license of Ambig-SWE (arXiv 2502.13069). It
  pairs each issue of SWE-bench Verified with a twin that lacks needed
  information. So each issue has a label: the critic should ask, or it
  should not. Missing information is near to hone's "fork that the sketch
  left open", and it is not the same thing. Say in the note how well the
  two match on twenty pairs that you read yourself.
- If the license allows it, write a fetch script with a pinned revision.
  Do not commit the dataset.
- Fill `docs/field-log.md` from the 220 real sessions. Look for gate
  blocks, stops, a mention of `.hone-off`, and a correction by the person.
  Each real misjudgment of a critic becomes a case. Count per hook how
  often it fired, and judge each block as right or as a false alarm. Step
  5 needs that table.
- Redact what you write into this repository. An entry names the hook, the
  block, and your judgment. It names no consumer repo and quotes no file
  content. A case that comes from a real session gets new names and new
  content that keep only the shape of the misjudgment.
- Split the data into train, validation, and held-out. hone's own
  `plan-critic` cases go into validation. The model that rewrites never
  sees the held-out part.
- Measure the seed first: the shipped `plan-critic` on 50 pairs. If it is
  right on more than 90 percent of both labels, there is no headroom. Then
  stop, write that down, and ask the maintainer before you go on.

Done when the split exists and a note has the seed's numbers.

### 3. The section splitter

A script under `evals/optimize/` that splits a prompt file into named
sections and joins them again. A test in `test/` with no model call proves
that split and join give back every shipped prompt file byte for byte.

### 4. Harder scenarios of our own

The aim is room on the outcomes where opus is at the ceiling today:
*transparent*, *correct*, and *well structured* apart from `cc_pile`. Do
not build a second scenario for the pile of complexity before the first
one has been used. So a new scenario must
pass one test before it stays. Run it three times on the bare arm and
three times with hone, on claude-opus-5. If both arms pass every run, the
scenario gives no room, and it goes or gets harder. This is the rule of
`evals/README.md`, *A case must discriminate*, applied to the lab. So
build the bare arm of `evals/lab/run.sh` first, here, with its test in
`test/lab_test.sh`.

Each family below gets three attempts. If the third attempt gives no room
either, write a note under `docs/spikes/` and go to the next family.

- *Generated families.* Give `seeded-prose` and `untied-sentence` a
  generator with parameters: the language, the domain, the repeated value,
  and the place where the repeat hides. Add a Note that contradicts
  another and a stale Decision as distractors. One generator gives fifty
  cases.
- *Real bases.* Seed from a pinned open-source repository of 5,000 to
  20,000 lines in place of a fixture of a hundred lines.
- *One sequence scenario.* Five to ten Plans in a row on one repository.
  Grade only the end state: true docs, no duplicate, no pile of
  complexity, each change revertible, and the total cost. hone's claim is
  about the codebase after many changes, and no scenario tests that today.

### 5. Structure: what each part buys

[*The structure layer*](#the-structure-layer) has the method. In order:

- Extend `--without` of `evals/lab/run.sh` from hooks to agents, loop
  steps, and land gates, through the variant script. `test/lab_test.sh`
  proves it with no model call. The bare arm exists since step 4.
- Run the bare arm once over the whole lab.
- Switch off one part at a time, the costly parts first: the nested
  review, the `consolidate-critic`, the consolidate step, the
  `plan-critic`, verify. Use only the scenarios that the part is meant
  for, three runs per arm. One such comparison costs about 15 to 40
  dollars, so print the estimate first.
- Judge the guards by the three-part rule of the design section, with the
  hook table of step 2. Run their ablations on the models below the floor.
- Run the whole lab on the lean variant.

Done when a note under `docs/spikes/` has the table of parts against
goals and costs, and names the variants on the front. Removing a part from
the shipped plugin is then an ordinary candidate, with its upgrade path.

### 6. Pilot: GEPA on the `plan-critic`

- A Python project under `evals/optimize/`, run with `uv` only. Never use
  `pip`.
- The adapter calls `evals/run.sh` for the rollouts. The rewriting model
  is a call to `claude -p`, so it runs on the maintainer's plan. Check in
  the GEPA docs that `reflection_lm` takes a callable.
- Objectives: correct rejections, correct approvals, and `words`.
- A single call is cheap, so set `reflection_minibatch_size` to 8 or more.
  The default of 3 is too small against the noise that
  `evals/README.md` records.
- The rewrite prompt may cut, shorten, or reword. Without `words` as an
  objective, rewritten prompts tend to grow.
- Lock each section that no case aims at. The search may not rewrite or
  cut a locked section. The maintainer decided this on 2026-09-20. The
  cases say nothing about such a section, so a cut would look free and
  prove nothing. On 2026-09-18 the cases held five sections of the
  `plan-critic` (`docs/spikes/2026-09-18-section-ablation-on-opus.md`). A
  section becomes free when step 2 gives it a case that discriminates. The
  same rule holds for the search of step 8.
- Keep the run directory under `/var/tmp/hone-optimize/`, outside every
  project, for the reason in `evals/lab/README.md`, *Where the sandbox
  lives*.
- Score each version on the front again: on the held-out part, and with
  `bash evals/run.sh plan-critic --votes 3 --holdout --prompt-file`.

Done when a note under `docs/spikes/` shows the front as a table, or says
why no front came out. A pilot that fails cheaply is a good result too.

### 7. Build tier 2 for the run skill

Depends on step 1. Turn recorded lab sessions into decision-point cases,
about 30 to start. Lab sandboxes under `/var/tmp/hone-lab/` may be gone,
so run the lab again where needed. Step 1 showed that `history_file` works
with hone: one resumed case took 7 seconds and 6 cents. It set three
limits. A decision point must lie before the review step, because the
nested review cannot reach the API under the runner. A grader that looks
for a commit must match `git -C <path> commit` too. A `check.sh` must
grade a copy of the kept workspace, never the workspace itself.

### 8. GEPA on the run skill

Search inside the structure that step 5 chose. Search on tier 2. The
task model may be claude-sonnet-5 where opus is at the ceiling, because it
is cheaper and fails more often. Score every version on the front again
on claude-opus-5. Check the two or three versions that might ship in the
full lab. The chosen version then goes
through `bash evals/candidate.sh decide` and the gates in
`.claude/rules/releasing.md`, as any change does.

### 9. Optional: SlopCodeBench, once, with and without hone

`docs/spikes/2026-09-18-slopcodebench-first-look.md` has the scope: about
250 dollars and a day of Docker setup. A critic of that benchmark says it
passes no handoff document between sessions. hone's Notes and Decisions
are such a handoff, so this is the one public benchmark that tests hone's
main claim. Only on the maintainer's word.

## Rules for whoever works on this

- Build no new probe, fixture, or harness feature outside these steps.
- Every run uses the maintainer's Max plan, not API money. A dollar figure
  in this file is the equivalent in plan usage. The maintainer said on
  2026-09-20 that a lot of plan usage is fine. So print the estimate before
  a run, and do not wait for an answer. Stop when the plan's limit blocks a
  run, and go on when the limit resets.
- Commit each finished step to `main` without asking. Do not push. A push
  needs the maintainer's word.
- You may read anything in the four consumer repos and in their session
  transcripts: code, Plans, Notes, Decisions, and git history. The
  maintainer said so on 2026-09-20. Use it for cases, scenarios, and real
  bases. Never write to a consumer repo. Material that you copy from one
  stays under `/var/tmp/`, as a dataset does. What enters this repository
  follows the redaction rule of step 2.
- Public data is material for training, validation, and probes. It never
  gates a release. That decision of 2026-09-19 stands.
- Never read a held-out case while you edit prose, and never show one to
  the model that rewrites.
- GEPA changes text only. The structure layer switches whole parts. The
  code inside a hook or inside `scripts/worktree.sh` is outside both.
- Switch a safety hook off only in a lab sandbox, never in a real
  repository.
- Nothing under `evals/` ships, so none of these steps needs a version
  bump. A prompt version that ships does.
- Skipped on purpose: the SWE-bench family measures task solving, which
  hone barely moves. The public code review benchmarks measure
  Anthropic's `/code-review`, and hone only writes its brief.

## What the maintainer must decide

None of these blocks steps 1 to 4 or the pilot of step 6.

- *May hone land honest code beside a test that it reports as wrong?* It
  is open in `docs/roadmap.md`. Only the land gate can change the 0 honest
  landings of 20 on ImpossibleBench, and prose cannot. Widening that probe
  to the full LiveCodeBench half waits for this answer.
- *May a section with no case and no field-log incident be cut?* Today it
  stays, and the search holds it locked (step 6). Ask this again after
  step 2, with the list of sections that still have neither.
- *Which parts are not up for removal*, whatever the numbers say. A
  likely list: the guard on the primary tree, the grant gate, and the
  proof gate. Step 5 measures them all the same, and it proposes to
  remove none of them without this answer.

## How I'll know it works

- Step 6 yields a front for the `plan-critic` with at least two versions
  that differ from the shipped one. Their scores hold on the held-out
  part.
- Step 5 yields a table that says for each part what it buys and what it
  costs. The maintainer can answer from it whether hone needs all its
  checks.
- One version from a front passes `candidate.sh decide` and ships.
- The field log has entries, and at least one became a case.
