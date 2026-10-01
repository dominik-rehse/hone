# Roadmap: what is open

This page lists what is open in the work on hone itself, and what the
maintainer decided. Each item says what happens, how we know, and what the
next step is. [*Goals*](model.md#goals) has the outcomes that hone works
for. [`development.md`](development.md) says how a change is judged,
and [`releasing.md`](../.claude/rules/releasing.md) has the
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

## Open

### Defects with evidence

#### MAIN loses track of its SUB sessions under herdr

- What happens: under herdr, a MAIN session starts one SUB session per
  Plan. Since 0.70 MAIN is the coordinator of `/hone:coordinate`. MAIN must watch each SUB until it lands or stops
  ([the coordinate skill](../skills/coordinate/SKILL.md)). MAIN often ends its
  turn with no watch on a running SUB. Then a SUB that stops at a gate
  waits for the person, and nobody tells the person.
- How we know: [the 2026-09-28 note](spikes/2026-09-28-main-tracking-of-subs.md)
  read 7 MAIN sessions. 13 stops or lands reached MAIN only when the
  person asked. 12 times a SUB needed the person and got no notification.
  One sign-off waited 7.5 hours.
- Where it comes from: MAINs did not use `herdr agent wait`, because a
  harness memory said that it returns early. It returns at once on a SUB
  that is already idle ([the 2026-09-29 note](spikes/2026-09-29-herdr-wait-semantics.md)).
  Each MAIN wrote its own watcher, and each watcher had new bugs.
- Done: `land` notifies the person at a gate (0.67.0). In 0.69.0,
  `scripts/coordinate.sh` holds one ticker and one wait for every MAIN, and
  the `watch` hook blocks a MAIN that ends its turn with no wait. The
  ticker sends the notifications from a script, so the `bash-guard` no
  longer sees them. The skill forbids a new `land` after a stop unless the
  person asks. `test/coordinate_test.sh` replays the three field shapes.
- What the field shows since: in a batch of about 34 Plans on 0.70.1 and
  0.71.1, `landed` and `stopped` reached MAIN within seconds. One stop
  reached MAIN only when the person asked, against 13 before ([the 2026-10-01 note](spikes/2026-10-01-field-data-coordinated-batch.md)).
  The channel is still thin, and MAIN filled each gap with a watcher of
  its own again:
  - MAIN ran the 0.70.1 scripts while its sessions ran 0.71.1. So
    `coordinate.sh planned` found no watch and exited 0 with no event in
    all 30 plan sessions. MAIN wrote about 49 pollers for the Plan file,
    and two hung on a renamed slug. Nothing warns a running MAIN of a newer
    install.
  - A stop that ends in text reaches MAIN only through `quiet`, after 600
    seconds. No event follows `stopped` when the session finishes its
    report, so MAIN wrote about 12 waiters for it.
  - `finished` fires at once for a consolidate pass, with its cuts
    unlanded (`coord_pass_finished`). `landed` carries HEAD of the caller's
    directory, not the merge commit, and named a wrong SHA twice.
  - The harness stopped MAIN's wait at its time limit 3 times. Once MAIN
    asked the person to send any message to wake it.
  - MAIN has no defined way to send a word to a session. It used `herdr
    agent prompt`, and a relayed `! attest` arrived as text.
  - MAIN guessed sign-off and grant state 5 times, because `list` and
    `board` do not read `.hone-proof/` or `.hone-grant/`.
  - `admit` ignores the predecessor a Plan declares. Two runs started
    early, and the run skill stopped both.
- Next step, the first priority on this page: give the channel
  redundancy, so that MAIN needs no watcher of its own.
  - A hook in each watched session pushes an event when its turn ends.
  - The ticker reconciles from git and the sign-off files: planned,
    landed with the merge SHA on main, signed, granted, and a consolidate
    pass whose cuts have landed.
  - The wait ends by itself before the harness limit, and says so.
  - `coordinate.sh` warns when the installed version is newer than the
    one MAIN runs.
  - One subcommand, such as `coordinate.sh send`, is the only path from
    MAIN to a session.
  - `admit` honors a Plan's declared predecessor.
  Each part gets a test in `test/coordinate_test.sh` that replays the
  field shape.
- Done in 0.72.0: a newer hone that writes an event warns a coordinator
  that runs an older one, once, and names `claude --resume <id>`.
  `planned` with no watch says so on stderr and still writes the event.
  `landed` names the merge that land made. `admit` holds a Plan whose
  predecessor has not landed, and `--after-ok <name>` lifts that hold on
  the person's word.
- Done in 0.73.0, each with a test in `test/coordinate_test.sh`: a
  watched session's Stop hook pushes `turn-ended` with the last line of
  its reply, so `quiet` is only the fallback. The ticker derives planned,
  landed with the merge SHA, signed, granted, and finished from git and
  the sign-off files, once each. `list` and `board` show sign-off and
  grant state. `wait` ends by itself after 9 minutes with exit 3.
  `coordinate.sh send` is the one path from MAIN to a session, and it
  refuses a `!` command. `admit` caps the runs in flight at 4.
- Still open: a Stop hook that blocks the stop (the gate, the nag) does
  not hold back `turn-ended`, so MAIN can wake on a turn that goes on. On
  2026-10-01 the maintainer chose no lab run for the redesign. Next step:
  read the next coordinated batch, and count the pollers MAIN still
  writes.

#### Parallel runs starve the suite lock, and the gate repeats work

- What happens: under `/hone:coordinate`, up to 7 runs share one suite
  lock. `flock -w` is not a queue, so a new verify can take the lock
  ahead of a land that waits. A land then ends in exit 5 (lock timeout)
  and tries again. `land` takes the lock before it checks the authority
  gate and the proof gate. So a land can wait half an hour only to stop at
  exit 7 or exit 8. `verify` writes no gate receipt, so the Stop gate runs
  `--all` again while the run only waits for the person.
- How we know: [the 2026-10-01 note](spikes/2026-10-01-field-data-coordinated-batch.md). One land hit exit 5 seven times over 2 hours 17
  minutes. Three lands waited 9, 9, and 36 minutes for exit 7 or 8. The
  Stop gate's repeat cost 30 and 32 minutes, and twice it hit the
  600-second hook timeout. Smaller shapes from the same batch:
  - On a fresh `hone/*` branch with no commits the gate runs `--all`. Its
    receipt is keyed on the version and the branch, never the tree, so it
    then reports "already passed" before the change exists.
  - Nested `/code-review` sessions run hone's Stop hooks. One held the
    suite lock for 3.7 minutes.
  - The gate blocked 12 times on a background subagent's red-green steps. 0.73.0 adds the cap: 4
  runs in flight by default.
    The cap of three counts one failure signature, so distinct reds pass
    it.
  - Each land empties the shared `hone-land.log`, and a concurrent land
    erased one run's exit-6 evidence.
  - Twice the tail of a red suite showed only passing lines.
- Next step, the second priority on this page:
  - a fair queue for the lock.
  - the authority and proof checks before the lock.
  - a gate receipt from `verify`.
  - no `--all` on a branch with no commits, or while the run waits for a
    person.
  - a cap on concurrent runs in `coordinate`.
  - a land log per change.
  - no hone hooks in a nested review.
  Each fix gets a test in `test/` that replays the shape.
- Done in 0.72.0, each with a test: a queue for the lock in which a land
  goes before a verify and keeps its place while a run holds the lock.
  The checks that need no `proof.sh` run come before the lock. Both person
  gates show in one stop (exit 8). A green `verify` writes the gate
  receipt. No suite runs on a `hone/*` branch with no commits. The land log
  is per change, and a failure tail shows the failing lines. A nested
  `/code-review` runs no gate and no nag. The progress line keeps a red
  verify red. Still open: the cap on concurrent runs, and the gate blocks
  on a background subagent's red-green steps.

#### The proof gate asks for sign-offs that prove nothing

- Checked on 2026-10-01: MAIN claimed that three changes landed with no
  proof run on the box. The claim was false. Each branch carried a
  `Proof: real-environment` trailer, and land ran `proof.sh` green. But a
  green automatic run leaves no line in the merge commit, so MAIN found no
  record, and the person re-ran four probes by hand. Two gaps are real:
  land never compares the trailer with the Plan's `Proof:` line, and an
  added probe with no trailer runs nowhere. Next step: record every green
  run in the merge commit, and treat an added probe as a request for proof
  that the adapter discharges with no sign-off.
- What happens: `land_proof_bootstrap` maps any non-`.sh` file under
  `scripts/proof-probes/` to the change's own probe command. A test file
  there is such a file. The project's `proof.sh` exits 3 on that command,
  and the person still signs. A comment-only edit to a probe also arms
  the gate. A sign-off is pinned to the tip, so a probe that did not
  change needs a new sign-off each time main moves. Land names the
  person's gates one at a time.
- How we know: [the 2026-10-01 note](spikes/2026-10-01-field-data-coordinated-batch.md). The person signed two attests that recorded "exit 3".
  7 of 9 area moves changed only a path in a probe comment. 8 of 40 probe
  runs failed the same way on main, and the person signed them. One run needed
  3 attests for an unchanged probe. One land stopped at exit 8 and then at
  exit 7. MAIN also relayed sign-off requests as the session's own claims,
  not as the verbatim output that `land.md` asks for.
- Done in 0.73.0, each with a test in `test/e2e_land_test.sh`: a gate
  for a file under `scripts/proof-probes/` names a probe that exists, so
  `proof.sh` no longer exits 3 on it. A sign-off carries when `git
  merge-tree` rebuilds the tip's exact tree from the signed commit. An
  added probe makes land run the adapter, and every green run writes a
  line in the merge commit. A sign-off counts only by the full commit id
  on its first line. `attest --file` reads the text from a file.
- Tried and removed: an exemption for comment-only probe edits, and one
  for README and test files. Three review rounds found ways for each to
  let a weakened probe land, and in the field repo 140 harness lines read
  probe text, so the comment exemption could never apply there. A
  sign-off for such an edit stays the cost.

#### A person's standing acceptance has no channel

- What happens: the person told MAIN early in a batch that they accept
  all plans and grants. hone has no way to record that. So the person
  still answered in the run tabs, and MAIN asked again what they had
  answered.
- How we know: [the 2026-10-01 note](spikes/2026-10-01-field-data-coordinated-batch.md). The person acted 22 times in run tabs in the first
  half of the batch. In the second half they gave 9 attests, 3 grants, and
  6 prompt answers. MAIN never offered `.hone-grant-auto`, and asked 4
  questions that the person had already answered. Once MAIN agreed to
  answer permission prompts for the person, which the coordinate skill
  forbids. Three runs ran `land` again after exit 6, citing a memory in
  the project, against `land.md`.
- Done in 0.73.0: the coordinate skill has a section on the person's
  word. MAIN offers `.hone-grant-auto` when the person delegates, keeps
  their standing answers, takes a yes only for the action the question
  named, and never answers a prompt in another tab. A field batch must
  show whether this holds.

#### Smaller defects from the coordinated batch

Each comes from [the 2026-10-01 note](spikes/2026-10-01-field-data-coordinated-batch.md).

- The nag tells MAIN, runs, and plan sessions that Plans are pending and
  to run `/hone:run`, 149 times in MAIN alone. Done in 0.73.0: the
  line shows only in the primary tree with no coordinator. A worktree's
  old copy of `.plans/` caused a count of 3 for 1.
- The nag's area-size count includes generated output, 11,699 of 17,764
  lines in one area. Done in 0.73.0: the count reads tracked files only
  and skips `linguist-generated` files and generated headers. A project
  marks its own generated files in `.gitattributes`.
- The global consolidate pass covered 17 of 32 merges, because its prompt
  names no base commit. Done in 0.73.0: the first run of a batch records
  the base, and the consolidate prompt names it. `finished` waits for the
  pass's cuts.
- Garden cut 3 tests as dead because the suite stayed green. That proves
  nothing for a test, and those cuts skipped review. All were safe on
  reading. Done in 0.73.0: in the garden skill a test cut is never
  mechanical, and it names the test that still covers the claim.
- `rules/workflow.md` allows `docs/` edits only at consolidate. Two Plans
  could not run, because a test checks that the docs cite `src` paths.
  The `plan-critic` caught both. Done in 0.74.0, on the maintainer's
  word: build may edit `docs/` where the change makes a line wrong or a
  test reads it. Consolidate still writes new Decisions and Notes.
- A flaky new test landed, and a later land's exit 6 caught it. Done in
  0.73.0: the run skill calls a red without a change in between a flake
  that the run made, and the run finds its cause first.

#### Two MAINs in one repository coordinate with no rule

- What happens: `parallel.md` checks overlap only within one MAIN's set of
  Plans. A claim covers only the same change. On 2026-09-27, two MAINs ran
  in one repository. They agreed on holds and file lists over Claude Code's
  cross-session messages, which hone does not mention. Once, a MAIN
  forwarded the other MAIN's acceptance to a SUB that had stopped at a
  Plan precondition meant for the person.
- How we know: [the 2026-09-28 note](spikes/2026-09-28-main-tracking-of-subs.md).
- Done in 0.70.0: `coordinate.sh admit` checks a change against every
  change in flight, whoever holds it: a worktree here, a session this
  repository watches, and each claim on the shared remote with its Plan.
  The coordinate skill says what a message between two coordinators may do. It may ask for a
  hold, send a file list, or wake the other MAIN. It never answers a stop
  that belongs to the person, and it never counts as proof of a land.
- Next step: read the next session in which two MAINs share a repository.
  Look for a message that stands in for the person.

#### The `untied-sentence` check grades a true negation as stale

- What happens: the lab scenario `untied-sentence` (see
  [the lab README](../evals/lab/README.md)) changes a free-shipping
  threshold from 100.00 to 150.00 EUR. Its `check.sh` then reads each
  sentence in the docs that names a threshold. It grades a sentence that
  names the old value as `stale`, which means false today. A run on
  0.66.0 rewrote the Decision to say that the threshold "does not reach
  down to 100 EUR". That sentence is true, and the check graded it
  `stale`, so `docs_true` came out `no`.
- How we know: the release pass of 2026-09-28 failed this one scenario.
  The sandbox was `/var/tmp/hone-lab/20260928-121729/untied-sentence`.
  The Decision in its repo holds only true sentences.
- Next step: teach `sentence_state` in that `check.sh` to read "does not
  reach down to" and similar negations as `history`. Then regrade the
  kept sandbox with `--regrade`, and make sure that the check still fails a
  sentence that states 100 EUR as today's rule.

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
  needs the `loop` unit suite.

#### On claude-opus-5-5 the loop sometimes starts a second review

- What happens: the run skill starts the nested `/code-review` in the
  background, and says to wait while its output file is missing. On
  claude-opus-5-5 one run dropped the `cd` into the worktree from the
  command. It then read the empty `.part` file as the end of the task, and
  started a second review while the first still ran. Both reviews came back
  valid. So the cost is a second review, and not a wrong verdict.
- How we know: the lab scenario `bypass-hook` failed its check that the
  review runs once, in 1 of 2 runs on 2026-09-25
  ([note](spikes/2026-09-25-first-pass-on-opus-5-5.md)). The unit case
  `review-fanout-temptation` held at 3/3, so the unit suite does not catch
  it.
- Next step: run `bypass-hook` and `defect-in-hunk` five times each on
  claude-opus-5-5 to get a rate. If it stays above zero, add a unit case
  where the output file is missing and the task still runs. Then reword the
  wait sentence in step 5 of `skills/run/SKILL.md` until the case holds.

#### A stop outside `/hone:run` has no rule for its report

- What happens: the run skill demands that a stop report ends with the one
  action that the run recommends. A session that is not a run has no such
  rule. That covers `/hone:plan`, `/hone:setup`, and a plain request.
- How we know: in the scenario `hand-merge`, one run on sonnet offered the
  person two routes and recommended neither. In `plan-fork`, one run of
  eight wrote that its rejected Plan was "written and on disk", while it
  recommended the other build.
- Why it waits: on opus this is rare. The fix would move the one-action rule into `rules/workflow.md`,
  which every session reads, so it costs words in every session.
- Next step: collect cases in the field log. With three or more on opus,
  build a scenario or a test that replays them, and make the change.

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
- Next step: the likely fix is one sentence in the refactor step of the
  run skill. It owes the `loop` unit suite. The measure `cc_pile` can show
  a gain. An exact check would need a complexity tool per language, which
  is a new tool, so rule 4 in `development.md` does not cover it.

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
- A smaller gap in the same skill: in a Python project, `scripts/setup.sh`
  adds neither `.venv/` nor `__pycache__/` to `.gitignore`. No run has
  committed one so far. The seed of `python-structure` adds them itself.

#### Two guards still give false alarms in real use

Field data counts each block in real sessions: about 220 sessions in
[the 2026-09-20 note](spikes/2026-09-20-field-data-from-real-sessions.md),
and 37 more in
[the 2026-09-25 note](spikes/2026-09-25-field-data-since-0-58.md). A false
alarm is a block on a command that did nothing the hook exists to stop.
Both guards also made real catches that no other part could make, so the
work is to fix the shapes, not to remove a guard.

Fixed in 0.62.0, each with a test in `test/hooks_test.sh` that replays
the shape:

- The `nag` skips links inside code, prints its full list once per session
  and tree, and reads a Plan whose change has a worktree as active work.
  Its 342 wrong lines of the first note came from the link check and from
  repeats.
- The gate's suite-lock block names the lock and not "another session",
  and it counts toward the cap of three blocks. About 20 blocks had blamed
  another session for the run's own background land.

Reverted in 0.62.1, and rebuilt in 0.63.0. 0.62.0 made
the `bash-guard` judge each simple command in the tree it runs in, and a
review then let about twenty command shapes that move the primary branch or
HEAD past it: a `cd` after `&&`, `||`, or `|`, a `git` command inside
`bash -c` or `eval`, and a `--work-tree` that overrides `-C`, among others.
The rebuild keeps the old whole-line rules as the default. Where one of them
would ask, an analysis replays the command, and it passes the command only
when it models every part (the header of `hooks/bash-guard.sh` lists what it
gives up on). Every shape of the review has a test, and each one asks. The
false alarms of the 2026-09-25 note pass: a merge or an abort in a scratch
worktree or clone, a path-scoped unstage, a package install in a scratch
directory, a formatter on a variable set to a Plan, a heredoc commit
message, a read of `.hone-grant/` inside `$(...)`, and a scratch check
config outside the repository. The check-config ask now names the file.

Fixed in 0.64.0: moves in the primary tree that the
old whole-line rules missed. They read the tree from one leading `cd` and
from literal `-C` paths, and the analysis only ran where they already
asked. So these passed: `(cd <scratch> && git merge x); git merge y`, a
`git -C "$X" merge` with `X` set to the primary tree after a `cd`, `sudo
git merge` or `command git merge` after a `cd`, a push from a scratch
clone whose origin is the primary tree, any command in a subdirectory of
the primary tree, and `git -C <primary> checkout`. A new last rule runs the
analysis on any command that names a guarded command or a push. It asks
when the analysis finds a move in the primary tree, or a guarded command
inside a runner such as `sudo`. A push counts when its destination is this
repository. A replay of 639 real commands added 5 asks, all right
([the 2026-09-26 note](spikes/2026-09-26-bash-guard-holes-replay.md)).
The same change lets `T=$(ls -d <glob> | tail -1); cd "$T"` pass when the
glob finds one scratch tree. Each shape has a test.
Next step: release it, then count the asks in the field again.

Fixed in 0.64.0: the `dirty-guard` now records the dirty protected
paths before each shell command, with a hash of each, and blocks only on
those the command changed. One old uncommitted file blocked 30 read-only
commands in the first note, and another session's half-finished merge was
blamed on unrelated commands in the second. Both shapes now pass. The skip
of a merge in progress stays reverted, because a `touch` of the merge
marker let a staged write past it. The comparison trusts no marker, and a
test replays that bypass. With no record of the tree before the command
(no ids in the hook input), the hook blocks on every dirty protected path,
as before. Next step: release it, then count its fires in the field again.

Fixed in 0.65.0:

- Rule 5 of the `bash-guard` fails closed where the analysis gives up.
  A move hidden in a loop body, an `if` or `case` branch, or a function
  passed before, as in `cd <worktree>; for x in 1; do cd <primary>; done;
  git merge y`, because the analysis stopped reading at the loop. Now
  rule 5 reads the rest of the command without order (the "reach" in
  `hooks/bash-guard.sh`). It collects every directory the shell may stand
  in there, judges each guarded command in all of them, and asks on a
  directory or a push it cannot resolve. Before the point where the
  analysis gives up, it keeps the exact order, so a harmless loop after a
  merge in a worktree still passes.
- A copy that only reads a protected file passes (`cp scripts/proof.sh
  /tmp/x`). A copy into one asks, also by its directory (`cp x/proof.sh
  scripts/`, `cp -t scripts x/proof.sh`), which passed before. A link to
  one still asks, because a write through the link lands in the file.

Each shape has a test in `test/hooks_test.sh` that fails on 0.64.0.
A replay of 705 real commands first found 20 new asks, 19 of them false.
Most were a loop that cds into each of several repositories on a loop
variable. The reach now reads such a variable with each of its values,
and the walk follows a `cd ..` and a directory the command makes. After
that, the replay adds 2 asks and removes 4, and every change is right
([the reach note](spikes/2026-09-26-bash-guard-reach.md)).
Next step: release it.

One older gap stays open. A push to a local path that does not exist yet
passes, even when an earlier `git worktree add` of the primary tree in the
same command makes that path. It predates 0.65 and did not show in the
replay. Next step: record the path that a `git worktree add` makes, and
judge a push to it as a push into this repository.

Still open:

- The `dirty-guard` blamed no command for a write that lands after the
  command returns, such as one from a background job, because the next
  command's record already held the path. Two calls of one session that
  ran at the same time each reported the other's write. Fixed in 0.65.0:
  a baseline per session in `.git/hone-dirty/` holds what the
  session's last check saw. A change that is in no command's span blocks
  the next check once, as outside the last command, with no restore. The
  first command of a session only writes the baseline, so older work never
  blocks. Parallel calls report a change once, and the block says another
  call may have made it. Tests in `test/hooks_test.sh` cover both gaps.
  What stays open: a background write that lands during a later command
  is still blamed on that command. A session that is running when another
  session leaves a merge half done gets one block for it. A command that
  another hook denied leaves its record, and for ten minutes a block in
  that session wrongly adds that another call ran at the same time.
  Next step: release it, then count in the field how often the outside
  block fires and whether its writer was a job, a person, or a session.

- The `bash-guard` still denies a sabotage token anywhere outside a commit
  message or a sign-off text, a read of the hooks-path key included.
- A replay of the 76 field asks of 2026-09-21 to 2026-09-26 through the
  0.65 `bash-guard` still asks on 41
  ([the audit](spikes/2026-09-27-eval-lab-value-audit.md)). Shapes seen:
  a merge in a worktree whose path is `S=$(mktemp -d)`, `dprint fmt` on a
  file under `.plans/`, and a command that writes to Claude Code's own
  memory directory. The replay substituted a working directory for
  worktrees that no longer exist, so the count is rough. Next step: sort
  the 41 into right and false asks, and add a test per false shape.
- The `bash-guard` still asks when a command uses a variable set in an
  earlier Bash call. This ask is right, and nothing is left to fix. Each
  call starts a fresh shell, so the variable is empty there. `cd ""` then
  fails, so a later command after `;` runs in the shell's directory, and
  `git -C ""` stays in it. The fix is on the agent's side: set the
  variable in the same command.

Seen on 0.70.1 to 0.71.1 ([the 2026-10-01 note](spikes/2026-10-01-field-data-coordinated-batch.md)). Each ask stopped an unattended run:

- A formatter on an unresolved `$F` in a worktree: 97 minutes, and the
  message said "primary tree".
- `bun install --cwd <worktree>`: 54 minutes. The message said to run it
  in a worktree, and it already did.
- A Python heredoc whose text holds `git reset --keep`, read as a move of
  HEAD: 8.7 minutes.
- `grep "chmod" scripts/proof.sh`, read as a change to a protected file:
  2.5 minutes.
- A `sed -i` on a Plan with `stryker.conf.json` in its expression, read
  as a change to a check config: 11.3 minutes.
- `guard` rule 1b on a `stryker.conf.json` repoint that the Plan
  required: 20 minutes.

Done in 0.72.0, each with a test in `test/hooks_test.sh`. The `--cwd`
install, the Python heredoc, the read-only `grep`, and the `sed` script
now pass, and so does `cd <scratch> && bun install >/dev/null`, a shape
from the next batch. The `$F` ask was right, so only its message changed.
The `stryker.conf.json` ask stays, and its message now names the Plan. A
replay of 96 crafted commands through both versions found no harmful
command that 0.72.0 passes and 0.71.1 stopped. The work closed four older
holes: `sed` writes by `-i` after the operands or by `w`, the `>|`
redirect, `bun --cwd <primary> add` with the option before the verb, and
`diff --output`.

How we know that the fixes hold in the field: we do not yet. The tests
replay each shape from the transcripts. Next step: after the release, read
the next field window and count fires per hook again.

#### Progress lines now come from a hook, and the lab has not measured it yet

- What happened: the run skill asked the agent to print a progress line
  when each step of the loop starts and ends. The model often starts a step
  in a message that holds only tool calls, so the line never appeared. In
  the field a person saw silence for up to 50 minutes. 10 of 23 finished
  field runs printed fewer than 5 of the 6 start lines
  ([note](spikes/2026-09-25-field-data-since-0-58.md)). The lab measure
  `progress_starts` (steps announced as started over steps reached, in
  `evals/lab/checks.sh`) read 1/6 to 3/6 on claude-opus-5-5 on 2026-09-25,
  also after better prose.
- What changed on 2026-09-26: hone prints the line itself. The step
  subcommands of `scripts/worktree.sh` (`add`, `verify`, `governed`,
  `review-scope`, `land`) queue it in `<git-common-dir>/hone-progress/`,
  one queue per session. `hooks/progress.sh` shows the queue as a
  `systemMessage` after each Bash call and at Stop. The run skill no longer
  asks the agent for the line. The final report stays the agent's.
- How we will know: the lab measure `progress_starts` now also reads the
  hook's lines, which the transcript logs as `informational` entries, and
  `hook_lines` counts them. The goal is 5/6 or better in every scenario
  that reaches land. The build step has no subcommand of its own, so its
  end shows only when verify starts.
- Garden, after 0.64.0: a garden change (`garden/<slug>`) now gets its own
  line too, on the chain the garden skill names: `worktree > cut > verify >
  land`. `add`, `verify`, and `land` queue it. The middle step reads
  `cut/repair` until the diff exists, then `repair` if the diff adds a line
  and `cut` if it only deletes. The garden skill no longer asks the agent
  for the line. No lab scenario runs garden, so only the tests
  (`test/e2e_land_test.sh`, `test/lab_test.sh`) show it works. The lab
  measure counts a garden line against four steps.
- Settled on 2026-09-26: the Claude Code hooks reference says `PostToolUse`
  fires only after a tool call succeeds, and a Bash command that exits
  nonzero fires `PostToolUseFailure` instead. So the progress hook and the
  `dirty-guard` check both run on both events. Before that, the
  `dirty-guard` never ran after a failed command.
- What the field shows: in a coordinated batch every `worktree.sh` step
  printed its line in all 34 runs ([the 2026-10-01 note](spikes/2026-10-01-field-data-coordinated-batch.md)). But the coordinator tab shows no
  progress, and MAIN relayed none. The line shows only when a Bash call
  returns, so a foreground land showed nothing for 4 to 10 minutes, once
  57. It sits in the scrollback and scrolls away. Next step: show the
  runs' lines in the coordinator tab, and find a place for the line that
  stays in view.
- Next step: in the next lab pass, read `progress_starts` and
  `hook_lines` in each `result.json`. For garden, watch the next field
  pass for the line, or add a lab scenario that runs `/hone:garden`.

#### The lab scenario `proof-gate` had a real fork at review

- What happened: the Plan asked `deliver` to retry a 5xx up to three
  attempts, and said the staging receiver answers 503 "for a few seconds".
  The nested `/code-review` found that the three attempts have no delay
  between them, so all three can fall inside that outage. Some runs then
  added a backoff, some declined the finding, and some stopped at review.
  A run that stops at review never reaches land's exit 7 (the proof gate),
  which is what the scenario tests.
- How we know: lab runs of `proof-gate` on claude-opus-5-5 ended in all
  three ways. The stop grew more common on 2026-09-25: none in the passes
  of 0.59.1 and 0.60.0, then 3 of 5 runs on 0.61.0 to 0.63.0. The same
  passes kept a duplicate once in `python-structure` (measure `dup=kept`),
  when the run declined the review's finding as cosmetic.
- What changed on 2026-09-26: the Plan in the scenario's `seed.sh` now says
  that the receiver's restart answers 503 to exactly one request, and asks
  for an immediate retry with no delay. So one 503 is the whole outage,
  and the review has nothing to fork on. The unit tests and the proof line
  are unchanged.
- Next step: in the next lab pass, confirm that `proof-gate` reaches exit
  7 in every run. Then delete this item.

#### The authority gate fires on a table rewrite

- What happens: SQLite cannot drop or change most columns in place, so a
  migration rewrites the table: create a new table, copy, drop the old one,
  rename. land read the drop as destructive SQL and refused with exit 8
  (the authority gate). Only a person may grant, so each such refusal
  stopped an unattended run.
- How we know: in [the 2026-09-25 note](spikes/2026-09-25-field-data-since-0-58.md)
  two of the gate's three fires were this idiom.
- What changed: land now reads a rewrite in a new migration file with
  `scripts/sql-rewrite.awk`. It lets the drop through only when the text
  shows five things. The file drops exactly the table it copied from. The
  copy is `INSERT INTO new SELECT * FROM old`, with no filter. The new table
  is renamed to the old name. The new table has the old columns in the same
  order with the same type affinity (SQLite's per-column type class, which
  decides whether a value is converted). And the old columns are known from
  the earlier migrations or a `schema.sql`.
  It also refuses on the loss paths it found: a cascading foreign key, an
  `INSERT OR IGNORE` or `ON CONFLICT` clause, a down section, and an
  earlier migration edited on the branch. The receipt or the refusal names
  each rewrite and the verdict. `test/sql_rewrite_test.sh` lists the cases.
- What the text cannot show: a column in the live database that no
  migration created, say one added by hand. A copy that lists its columns
  then drops it with no error. A copy written as `SELECT *` fails loudly
  instead, because the live table and the new one no longer have the same
  number of columns. So on 2026-09-27 the maintainer decided that only a
  `SELECT *` copy counts as lossless. A copy that names its columns fires
  the gate, and the refusal says why. Such a copy was lossless by the text
  alone before, so a migration written that way now stops for a grant.
- What the field shows: every fire of the gate in the field came from an
  Atlas migration, and Atlas writes the copy with a column list. So the
  `SELECT *` rule exempts none of them, and each still stops for a grant.
  `scripts/sql-rewrite.awk` on the two migrations of 2026-09-22 and
  2026-09-23 answers "the copy names its columns"
  ([the audit](spikes/2026-09-27-eval-lab-value-audit.md)). On 2026-09-27
  the maintainer accepted that price: a grant per Atlas rewrite.
- Next step: after the next release, count the exit-8 stops in the
  maintainer's repos, and read every rewrite that land let through. A
  rewrite that should have fired is a defect in the reader, and it goes in
  `test/sql_rewrite_test.sh` first.

#### The test-first rule asks for a test of a fixture file

- What happens: rule 2 of `hooks/guard.sh` denies a new non-test file
  under `src/` that has no test. A fixture, such as
  `src/retrieval/__fixtures__/latch-worker.ts` or
  `background-strip.fixtures.ts`, is data for a test and not production
  code. The agent obeys and writes a test for the fixture.
- How we know: 5 of the 6 test-first denies in the field on 2026-09-21 to
  2026-09-26 were on fixtures, and about 11 tests of fixtures now sit in
  that repository
  ([the audit](spikes/2026-09-27-eval-lab-value-audit.md)).
- Next step: exempt a path under a `__fixtures__/` or `fixtures/`
  directory and a basename with `.fixture.` or `.fixtures.`, with a test
  per shape in `test/hooks_test.sh`.

#### A land that succeeds can return exit code 1

- What happens: land removes the worktree after the merge. When the
  Bash call stood in that worktree, the command ends with exit code 1
  after land printed "hone worktree: landed". The agent then reads a success
  under a failure code. The field log calls the getcwd case fixed in
  0.60.0, and this is what remains of it.
- How we know: 8 sessions of 2026-09-21 to 2026-09-26 show "Exit code 1"
  before "hone worktree: landed", some on 0.63.0.
- Next step: find which command after land's exit fails in a removed
  directory, and make land's own exit code the call's last word. A test in
  `test/e2e_land_test.sh` runs land from inside the worktree and checks
  the exit code.

#### The `consolidate-critic` once proposed cutting code that a Plan requires

- What happens: in one field run the critic proposed to remove a
  `MutationObserver` that the Plan required, and a person had to decline
  it. In the same window it proposed two more cuts that a person declined
  ([note](spikes/2026-09-25-field-data-since-0-58.md)).
- How we know it is not pinned: an eval case built from that run did not
  discriminate. The current prompt and the stub both answered CLEAN, 3
  votes of 3 each. A case that no baseline fails pins nothing, so it did
  not go in, and no prose was added.
- Next step: collect more such cuts in the [field log](field-log.md). A
  case needs a brief on which the stub proposes the cut and the prompt
  must refuse it.

#### The critics' verdict line drifted on 0.58.1

- What happens: the critics must end with the verdict on its own line. On
  0.58.1 they wrote a bolded verdict, a "Verdict:" prefix, prose after the
  verdict, or a file list last.
- How we know: [the 2026-09-25 note](spikes/2026-09-25-field-data-since-0-58.md).
  The 0.59.0 sample was clean, but it held too few reviews to call it
  fixed.
- Next step: count the verdict shapes in the next field window. If the
  drift returns, check whether the loop still reads such a line as the
  verdict, and tighten the output paragraph of the critic prompts.

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

Since 2026-09-27 real use is the main source of work, and `test/run.sh`
is the regression gate. No item in this section starts without the
maintainer's word
([the audit](spikes/2026-09-27-eval-lab-value-audit.md)).

#### Fails from real use

[`field-log.md`](field-log.md) collects what hone does wrong in the
repositories that use it, one dated line per incident. These fails are the
best source of new scenarios, because they are real. The first entries came
on 2026-09-20 from about 220 recorded sessions. More came on 2026-09-25
from 37, and on 2026-10-01 from a coordinated batch of 105. The counts
per hook are in
[the first field-data note](spikes/2026-09-20-field-data-from-real-sessions.md),
[the second](spikes/2026-09-25-field-data-since-0-58.md), and
[the third](spikes/2026-10-01-field-data-coordinated-batch.md).

#### Probes

- What exists: `evals/probes/impossiblebench/` runs ten tasks of the
  public benchmark ImpossibleBench, with hone and without it. We picked
  these ten because opus had cheated on them before. A pass runs each task
  once, or `--runs N` times.
- One task ends in a cheat on every release, because the probe's request
  makes the tests the authority. With a request that names the
  specification, hone refuses the cheat, and the lab scenario
  `spec-authority` guards that
  ([`spec-authority-first-runs`](spikes/2026-09-19-spec-authority-first-runs.md)).
- What it can show: only a large change, as long as a pass has ten single
  runs. No pass with more runs per task exists yet.
- When it runs: once for each new Opus, and a few times a year when the
  maintainer asks ([`releasing.md`](../.claude/rules/releasing.md)). A pass
  at `--runs 3` costs about as much as a lab pass. The benchmark's second half is built on SWE-bench. It needs Docker and
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

- *A reviewer from another model family.* The author and the reviewer are
  both Claude, so they may miss the same things. Reopen when real use
  shows a defect that the opus review missed.
- *hone on hone.* This repository does not use hone for its own work
  ([`development.md`](development.md), *Change briefs*). Setting that up
  is a project of its own, and nothing above depends on it.

## Decided

- *The `consolidate-critic` stays as it is* (2026-09-18). No unit case
  shows that the bullets proposed for removal change a verdict. A lab test
  of the removal would cost about 60 dollars, and the maintainer decided
  against it.
- *A cheap, exact check needs no measured gain* (2026-09-18). It is rule 4
  in `development.md`. Cheap means no model call and no new tool.
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
- *Real use leads, and the evals gate* (2026-09-27). Of 200 changes to
  the plugin, about 8% came from an eval or the lab, and about 45% from
  real use. The suites stay as a regression gate. No new benchmark,
  probe, ablation campaign, prompt search, or noise-floor measurement
  starts without the maintainer's word. This drops the program of
  `HANDOFF.md`, and git keeps the file. A guard change gets a code review before release
  ([the audit](spikes/2026-09-27-eval-lab-value-audit.md)).
- *The optimization tooling is gone* (2026-10-01). The maintainer removed
  the prose optimizer, the candidate procedure, the decision-point cases,
  the review bench, and the model floors. A release no longer runs the lab
  or the held-out cases. Git keeps the files.
- *Only a person records a grant* (2026-09-26). In the field the agent
  granted itself each of the 3 times the authority gate fired
  ([note](spikes/2026-09-25-field-data-since-0-58.md)), so exit 8 stopped
  nothing. The run now stops at exit 8 like at exit 7, and a Plan cannot
  authorize the change, because the agent helped write it.
