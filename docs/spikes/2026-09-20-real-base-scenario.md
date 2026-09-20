# Spike: does a real base give the lab room on *correct* and on `dup`?

**Date:** 2026-09-20 · **Status:** frozen. Written once, never maintained
against the code.

## Question

Every lab fixture holds about a hundred lines, and opus passes nearly every
scenario. Step 4 of `HANDOFF.md` asks whether a pinned open-source repository
of 5,000 to 20,000 lines gives room on *correct* and on the duplicate measure
`dup`. Room means that the two arms differ, or that the hone arm fails
sometimes.

## What I did

The base is [pallets/click](https://github.com/pallets/click), pinned at the
tag 8.5.0, commit `8b19813f2bfca99f1018a587a8cf54fc959f2e5d`. The license is
BSD-3-Clause. The tree holds 12,674 lines of source under `src/click/` and
15,800 lines of tests. `uv run pytest` runs 1,991 tests in 3 seconds, offline.
The package has no runtime dependency, so the hidden proof needs only
`python3`.

The seed fetches the one commit into a bare mirror under
`/var/tmp/hone-lab-bases/`, and it unpacks it with `git archive`. A second run
fetches nothing. The wheels go to a cache under the same directory, which the
fixture's `pyproject.toml` names, so a worktree of a run resolves offline. With
no mirror and no network the seed stops and says so, and the harness calls that
indeterminate. This repository commits no line of the base.

Each task hides facts that the Plan does not name, so that a run which does not
read the base gets them wrong. Every hidden fact sits in the base, and a
careful engineer who reads it gets the task right.

### Attempt 1: `click.config_option`

The Plan asks for a decorator that reads the default values of a command out
of a JSON file. The base already holds `Context.default_map`, the map that
click consults between the environment and a declared default, and
`utils.get_app_dir`, which names the per-user configuration directory.
`docs/commands.md` of the base documents the first one, nesting and all.

A run that uses the default map gets four things for free, and the hidden proof
reads all four. An environment variable beats the file. A string in the file is
cast to the parameter's type. `--help` shows what the command would really use.
The file of one call does not stay behind for the next call. `dup` reads
`ParameterSource`, which is click's own answer to where a value came from.
`appdir` reads whether `XDG_CONFIG_HOME` moved the search.

I built three end states by hand under `/var/tmp/hone-realbase/work/` and
graded each one. The reference reuse passes the proof with `dup reused`. A
hand-written version that sets each parameter's default passes seven of the
eight tokens and reads `dup copied`. A third one fails the proof outright.

`scb-check` does not see this duplicate. Both end states read `clone_loc 452`,
because the copy is of a mechanism and not of any lines. So the existing `dup`
of `python-structure` does not fit a real base, and this scenario measures
reuse behaviorally instead.

### Attempt 2: an `Environment` section in `--help`

The Plan asks for `Command.format_envvars`, one section listing the variables
that a command's options read. The hidden fact is
`Context.auto_envvar_prefix`. It gives an option a variable name that the
option itself does not declare. The name grows from the prefix and from the
names of the commands above it. The second measure compares the section against
the same rows through the base's own definition-list writer. A section padded
by hand differs where a name is longer than the column.

I built both end states by hand. The hand-padded one passes the whole proof and
reads `dup copied`, so the two measures are separable here.

### Attempt 3: `Group(prefix_matching=True)`

The third task changes how a group resolves a name, and it does not add a
function. `docs/extending-click.md` of the base holds a recipe for this, and
the recipe falls into two traps. The proof reads both.

The first trap: shell completion resolves commands through the same
`get_command`, in resilient mode. A version that calls `ctx.fail()` on an
ambiguous prefix makes completion raise. The second trap: a prefix must not
reach `ctx.invoked_subcommand`, which takes what `resolve_command` returns.
`dup` reads whether the ambiguity message ends with the base's own wording for
candidate names, which `exceptions._format_possibilities` writes.

Again I built both end states by hand. The recipe fails two of the seven tokens
and reads `dup copied`. The reference passes everything.

## Finding

Opus is at the ceiling on all three tasks, with hone and without it.

| attempt | arm | verdict | `correct` | `dup` | cost | time |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | bare | fail on hone's artifacts | yes | reused | $1.63 | 4m |
| 1 | full | pass | yes | reused | $7.49 | 20m |
| 2 | bare | fail on hone's artifacts | yes | reused | $1.04 | 2m |
| 3 | bare | fail on hone's artifacts | yes | reused | $1.17 | 3m |

A bare run cannot pass the verdict, because five checks read an artifact of
hone. So compare the arms by the measures, never by the verdict. `appdir` read
`reused` in both runs of attempt 1.

The bare run of attempt 1 wrote the reference implementation, 96 lines, with
the docs and 296 lines of tests, in four minutes. It used the default map and
the app-dir helper with no prompt. The bare run of attempt 2 found the auto
prefix in two minutes. The bare run of attempt 3 avoided both traps of the
recipe in three minutes.

Four more runs of attempt 1 died on the plan's usage limit after two minutes
each, at about $0.90, and the harness called them indeterminate. The limit had
reset before the run of attempt 3. So the table holds one complete run per arm
for attempt 1, and one bare probe for each of the other two tasks.

The one thing that does differ is the price. The full arm cost 4.6 times the
bare arm and took 5 times as long, for the same measures on every outcome. The
opus runs cost $14.93 of plan usage, the four dead runs included.

### And on claude-sonnet-5

Step 8 may search on sonnet where opus sits at the ceiling, and step 5 runs
some arms below the floor. So both tasks ran on sonnet as well.

| task | arm | verdict | `correct` | `dup` | third | cost | time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | bare | fail on artifacts | yes | reused | appdir reused | $1.00 | 3m |
| 1 | full | pass | yes | reused | appdir reused | $2.39 | 13m |
| 3 | bare 1 | fail on artifacts | yes | reused | collection no | $0.84 | 4m |
| 3 | bare 2 | fail on artifacts | yes | reused | collection yes | $0.69 | 3m |
| 3 | bare 3 | fail on artifacts | yes | reused | collection yes | $0.56 | 2m |
| 3 | full 1 | pass | yes | reused | collection yes | $2.47 | 12m |
| 3 | full 2 | pass | yes | reused | collection yes | $1.76 | 7m |
| 3 | full 3 | pass | yes | reused | collection yes | $1.98 | 9m |

Sonnet holds `correct` and `dup` in every run of both tasks, on both arms. The
first bare run of task 3 missed the collection of groups, which is a measure
that decides nothing. That looked like room, so task 3 ran to three runs per
arm. The next two bare runs held it. One run of six is noise, and the arms do
not differ. The sonnet runs cost $11.69.

So the base gives no room on sonnet either. Sonnet is the cheaper arm on this
base, at a third of the cost of opus and at two thirds of the time.

So this family gives no room on *correct* and none on `dup`. That holds for
claude-opus-5 and for claude-sonnet-5, on a base of this size, with a Plan that
states the API. A
precise Plan and a model that reads the code are enough. The haystack does not
hide the needle from it. Three attempts is what step 4 allows, so the family
stops here.

Two things would be worth trying if someone reopens this:

- Cut the Plan back to what a user asks for, and let the run derive the API.
  That widens what a run can get wrong, and it widens the unfair failures too.
- Take a base with weaker test coverage. Click's 1,991 tests catch almost
  everything a run breaks, so the run fixes it before the grading sees it.

## Where it landed

The scenario is `evals/lab/scenarios/real-base-click/`, which keeps attempt 1.
No task has more room than another, so the delivered one stays.
It runs by name only, through the `by-name` file that `evals/lab/run.sh` now
reads. It stays as the harness of this family and as a zero point, and it never
enters the release gate. `test/lab_test.sh` proves the seed's message and both
end states with no model call. Attempts 2 and 3 live in no file. This note
describes each one well enough to build it again. `docs/roadmap.md` carries the
open item.
