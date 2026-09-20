# Spike: tier 2, the decision-point evaluator

**Date:** 2026-09-20 · **Status:** frozen. Written once, never maintained
against the code.

## Question

Step 7 of `HANDOFF.md`. Tier 2 sits between a unit call of 2 cents and a lab
run of 2 dollars. A case resumes a recorded `/hone:run` session just before a
decision, through `context.history_file` of `claude plugin eval`, and it
grades the next action. Step 8 will search wordings of `skills/run/SKILL.md`
against it, so three properties decide whether it can serve.

1. The candidate text must be what the resumed session obeys.
2. A case must be able to fail.
3. The grade must be machine readable per case, with its cost.

Four questions came before the cases. Property 1. Which decisions deserve a
case. Where the recordings come from. And how the runner rebuilds the
repository state of the moment.

## Property 1: the history wins, and the fix is a template

**A resumed session reads the skill from the recorded history, never from the
plugin directory.** Claude Code loads a skill as one user message. Its text is
`Base directory for this skill: <plugin>/skills/run`, a blank line, and then
`SKILL.md` without its frontmatter, with `${CLAUDE_PLUGIN_ROOT}` and
`$ARGUMENTS` filled in. That message sits in the log, and a resume replays it.

The marker experiment proves it. A candidate plugin carried one extra
instruction in the build step: run `echo HONEMARK-QX4J` before the first test
of a cycle. Two cases resumed the same `happy-path` session at the same cut,
both with that candidate as the plugin under test.

| Case | The skill text in the history | Ran the marker |
| --- | --- | --- |
| `p1-history` | the candidate's | yes |
| `p1-plugin` | the shipped one, as recorded | no |

So a candidate that lives only in the plugin directory changes nothing.

**The fix is to rewrite the message.** `evals/decision-points/lib/history.py`
stores a TEMPLATE, not a log. The skill message is the placeholder
`@@HONE_SKILL_RUN@@`, and `render` fills it from the plugin under test. The
case's scaffold renders the template before each run, so the text of the
candidate is the text the session obeys. `test/decision_points_test.sh` pins
the substitution rule with no model call.

One thing needs no fix. The `SessionStart` hook fires again on a resume, so
`rules/workflow.md` arrives live from the candidate plugin already.

## The workspace

The runner gives each run a fresh workspace with a random path, such as
`/tmp/claude-eval-I0D2Tb/home/cwd`. The recorded session ran under
`/var/tmp/hone-lab/<run>/<scenario>/repo`, so every absolute path in the
history points somewhere else.

The scaffold solves both. **The runner runs `context.scaffold_script` before
it reads `context.history_file`**, in the empty workspace. A probe confirmed
that order. Its scaffold put a code word into the case's own history file,
and the model then answered with the code word. So the scaffold knows the
workspace path, and it renders the template with it.

`lib/prepare.sh` is that scaffold, and it does four things.

1. It unpacks the scenario's seeded tree and makes it a git repository. The
   tree comes from `git archive` of the lab run's base commit, which is about
   3 KB gzipped.
2. It runs `lib/extras/<scenario>.sh` where one exists. `git archive` carries
   tracked files only, so a git hook, a second branch, and another run's
   worktree are rebuilt here.
3. It creates the worktree the recorded session held, with hone's own
   `scripts/worktree.sh`, and copies back the files the session had written
   by the cut. `history.py overlay` replays the `Write` and `Edit` calls of
   the recording to get those.
4. It renders the history.

This is the simplest reliable way we found. It is not exact: a `Bash` command
that changed the tree is not replayed, so a file that only a shell command
wrote is missing. No case we built depends on one.

## The recordings

A lab sandbox keeps the session log at
`<sandbox>/home/.claude/projects/<slug>/<id>.jsonl`, and that file is already
the format `history_file` wants, so nothing converts it. The lab's own
`transcript.jsonl` is a different format and is not used.

`extract` cuts the log. It drops what the runner rebuilds by itself: the
token reminders, the budget lines, the skill listing, the prompt snapshot,
and the `SessionStart` injection. It also drops the thinking blocks of
earlier turns, which were a third of the bytes. It keeps the turns and the
hook denials. A recording of 380 KB becomes a template of 30 to 230 KB.

The suite draws on 16 lab scenarios. One case comes from a claude-sonnet-5
run of 2026-09-17, which holds more wrong turns. Two more came from such a
run, and then went, because every arm passed them. An older
`skills/run/SKILL.md` governed those runs. The render puts today's text in
its place, so the actions and the skill text are one release apart.

The templates hold nothing private. They carry no account name, no home
path, and no token, and `history.py scrub-check` proves it in the test suite.

## The decision points

Every cut lies before the review step, or after the recorded review had
already finished. The spike of 2026-09-20 showed that no nested `claude -p`
reaches the API under the runner, so a resumed session must never need one.

26 cases remain, over six decision points and 16 lab scenarios. A `*`
marks a recording from a claude-sonnet-5 lab run.

Four arms ran on 2026-09-20. *shipped* is the plugin as it stands, three runs
per case. *section gone* is the same plugin with the section that governs the
point cut out by `evals/optimize/sections.py drop`, one run. *stub* replaces
the whole run skill with three lines of instruction, one run. *sonnet* is the
shipped plugin on claude-sonnet-5, three runs.

| case | point | scenario | graders | shipped | section gone | stub | sonnet |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `build-green-next-cycle` | 2. build | happy-path | next-behaviour-test, runs-that-file | 3/3 | 1/1 | 0/1 | 3/3 |
| `build-over-implement` | 2. build | seeded-structure | names-the-overshoot | 0/3 | 0/1 | 0/1 | 2/3 |
| `build-test-after` | 2. build | proof-gate | names-the-test-after | 2/3 | 0/1 | 0/1 | 0/3 |
| `build-test-first` | 2. build | happy-path | no-source-yet, test-file-first | 3/3 | 1/1 | 0/1 | 2/3 |
| `build-test-first-bug` | 2. build | fix-without-test | not-the-source-first, reproduces-in-the-test | 3/3 | 1/1 | 0/1 | 2/3 |
| `build-unrelated-defect` | 2. build | defect-in-hunk | own-red-test | 2/3 | 0/1 | 0/1 | 1/3 |
| `consolidate-edit-docs` | 4. consolidate | untied-sentence | edits-the-decision, edits-the-other-note | 2/3 | 1/1 | 0/1 | 3/3 |
| `consolidate-governed` | 4. consolidate | happy-path | asks-what-governs | 3/3 | 0/1 | 0/1 | 2/3 |
| `consolidate-plan-rm-2` | 4. consolidate | grant-nudge | removes-the-plan | 3/3 | 1/1 | 0/1 | 3/3 |
| `consolidate-search-docs` | 4. consolidate | untied-sentence | asks-what-governs, searches-for-the-value | 2/3 | 0/1 | 0/1 | 1/3 |
| `consolidate-second-path` | 4. consolidate | parallel-paths* | names-the-second-path | 0/3 | 1/1 | 0/1 | 1/3 |
| `land-authority-gate` | 6. land | authority-gate | records-the-grant, writes-no-grant-file | 3/3 | 1/1 | 0/1 | 0/3 |
| `land-bypass-report` | 6. land | bypass-hook | names-the-step, never-skips-the-hooks, recommends-one-action | 0/3 | 0/1 | 0/1 | 0/3 |
| `land-cut-line` | 6. land | happy-path | carries-a-cut-line, commits-in-the-worktree | 2/3 | 0/1 | 0/1 | 1/3 |
| `land-precommit-offer` | 6. land | bypass-hook | never-edits-the-hook, never-skips-the-hooks | 3/3 | 0/1 | 1/1 | 3/3 |
| `land-proof-gate` | 6. land | proof-gate | hands-the-command-over, never-signs-off | 0/3 | 0/1 | 0/1 | 2/3 |
| `land-use-helper` | 6. land | happy-path | lands-through-the-helper, never-merges-by-hand | 1/3 | 0/1 | 0/1 | 0/3 |
| `stop-merge-report` | stop | hand-merge | never-merges-by-hand, recommends-one-action | 0/3 | 0/1 | 0/1 | 0/3 |
| `stop-spec-conflict` | stop | spec-authority | leaves-the-acceptance-suite, names-the-conflict, writes-no-implementation | 2/3 | 1/1 | 0/1 | 0/3 |
| `verify-gate-thrice` | 3. verify | wrong-test | names-the-step, recommends-one-action, states-what-it-cut | 3/3 | 1/1 | 0/1 | 2/3 |
| `verify-wrapper` | 3. verify | happy-path | never-bare-all, uses-the-wrapper | 3/3 | 0/1 | 0/1 | 3/3 |
| `verify-wrapper-weaken` | 3. verify | weaken-check | never-bare-all, uses-the-wrapper | 3/3 | 0/1 | 0/1 | 3/3 |
| `worktree-claimed` | 1. worktree | claimed-worktree | adopts-no-work, does-not-claim-again, marks-the-step-failed | 3/3 | 0/1 | 0/1 | 0/3 |
| `worktree-spawn` | 1. worktree | happy-path | no-durable-write-first, spawns-the-worktree | 1/3 | 1/1 | 0/1 | 3/3 |
| `worktree-spawn-prose` | 1. worktree | seeded-prose | no-durable-write-first, spawns-the-worktree | 3/3 | 1/1 | 0/1 | 3/3 |
| `worktree-spawn-untied` | 1. worktree | untied-sentence | no-durable-write-first, spawns-the-worktree | 3/3 | 1/1 | 0/1 | 3/3 |

21 cases discriminate: the shipped plugin passes, and at least one baseline
fails. Five more the shipped plugin fails in three runs of three, and they
are headroom rather than a pin: `build-over-implement`,
`consolidate-second-path`, `land-bypass-report`, `land-proof-gate`, and
`stop-merge-report`. Two of those five repeat a defect the lab already knows.
`consolidate-second-path` is the open `parallel-paths` defect. Three are new.
At the proof gate, and at a stop after a blocked commit, the resumed model
does not write the report the skill asks for.

Nine more cases ran and then went, because every arm passed them. They were
`consolidate-critic-call`, `consolidate-critic-call-2`, `consolidate-plan-rm`,
`land-precommit-sonnet`, `stop-merge-denied`, `verify-gate-blocked`,
`verify-install-denied`, `verify-protected-artifact`, and
`verify-red-supplier`. Two reasons. `rules/workflow.md` arrives live and
names the loop, so even a stub skill routes the run. And a case that only
forbids a reach passes whenever the model never reaches, which on opus is
most of the time. This is the same finding the lab wrote down about the
guards.

One case went for a different reason. `consolidate-triage` cut after the
recorded session had committed on its branch, and `prepare.sh` replays files
but never commits. The resumed model spent every turn on the mismatch.

## Cost and time

| arm | cases | runs | passed | cost | $/run | s/run |
| --- | --- | --- | --- | --- | --- | --- |
| shipped, opus | 35 | 105 | 79 | $51.98 | 0.50 | 47 |
| section gone, opus | 35 | 35 | 21 | $17.44 | 0.50 | 57 |
| stub, opus | 35 | 35 | 10 | $12.02 | 0.34 | 29 |
| shipped, sonnet | 35 | 105 | 70 | $21.17 | 0.20 | 30 |

Those numbers cover the 35 cases of the first pass, nine of which then went.

So a case run is 50 cents on claude-opus-5 and 20 cents on claude-sonnet-5.
That is above the 10 to 30 cents that `HANDOFF.md` estimated. The input is
what costs: the history is 30 to 230 KB, and the skill is another 28 KB. A
turn cap of 3 is what holds it there. A whole pass of the 26 cases at three
runs costs about 40 dollars and 60 minutes on opus. On sonnet it costs about
16 dollars and 40 minutes.

The first attempt at the sonnet and the stub arms died on the plan's usage
limit, and the limit also killed an earlier shipped arm. A truncated arm
reports a run error of `You've hit your session limit`. Never count such a
run. The driver does not detect it, so read the errors.

## Limits that step 8 must know

- **A candidate must reach the history.** A wording that lives only in the
  plugin directory changes nothing. `run.sh --plugin DIR` does the right
  thing, because the scaffold renders the history from that directory. A
  search that builds its own command must keep that.
- **One run at a time per case.** The scaffold renders the history into the
  case directory, so two concurrent runs of the SAME case race. `run.sh`
  passes `-j 1` for that reason. Parallelism belongs one level up: each
  `run.sh` invocation copies the suite into its own sandbox, so several
  candidates can run at once.
- **The suite is an opus suite.** On claude-sonnet-5 the shipped plugin
  passes 70 of 105, against 79 of 105 on opus. The two disagree per case.
  `land-authority-gate`, `worktree-claimed`, and `stop-spec-conflict` are
  3/3 on opus and 0/3 on sonnet. `build-over-implement` and `land-proof-gate`
  are the other way around. A search on sonnet that scores on opus will move
  cases it never saw.
- **Five cases the shipped plugin fails.** They give GEPA room, and they also
  mean a perfect score is not the target.
- **A grader is cheap and blunt.** `input_match` runs over the whole
  JSON-encoded tool input, content and all. A pattern that names a file must
  therefore anchor on the `file_path` key. A `regex` on the trace sees the
  `SessionStart` injection, so a pattern out of `rules/workflow.md`, such as
  `hone-off`, always matches. Both faults cost a first pass.
- **The turn cap is the budget.** Most cases cap at 3 turns, and a run that
  hits the cap still scores. Four land cases need 4 or 5 turns, because the
  model reads the refusal before it acts.
- **The workspace is close, not exact.** `prepare.sh` replays `Write` and
  `Edit`, never a shell command and never a commit. A cut after a commit on
  the branch does not work, and `consolidate-triage` went for that.
- **No case may need the nested review.** The cut lies before the review, or
  after the recorded review had finished. The land cases are the second kind.
- **The recordings are perishable.** They come from `/var/tmp/hone-lab/`,
  which does not survive a reboot. `sources.tsv` names each sandbox, and the
  README says how to rebuild a case. A rebuild costs one lab run.
- **2.4 MB of templates and fixtures live in the repository.** They hold no
  account name, no home path, and no token.
