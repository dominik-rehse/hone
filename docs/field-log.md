# Field log: where hone failed in real use

This page collects what hone did wrong in the repositories that use it. Each
incident is one line, and the newest line is first. A range sorts by its
last date, and an undated line goes below the dated lines of its block. A
line names no repository, because this repository is public. It has the
date or the date range, the hone version, the hook or the critic, and what
happened. Identical
incidents share one line with a count. When an incident becomes a lab
scenario, a probe, or an eval case, its line names it. A case path is below
`evals/`.

The counts and the method are in
[the 2026-09-20 field-data note](spikes/2026-09-20-field-data-from-real-sessions.md),
[the 2026-09-25 field-data note](spikes/2026-09-25-field-data-since-0-58.md),
and [the 2026-10-01 note on a coordinated batch](spikes/2026-10-01-field-data-coordinated-batch.md).
"Not recorded" in the version field means the source did not record it.
The MAIN incidents up to 2026-09-28 are counted in
[the 2026-09-28 note](spikes/2026-09-28-main-tracking-of-subs.md).

- 2026-10-01 · 0.71.1 · `coordinate` · MAIN asked whether to plan two
  items. On "yes" it also started two runs. The person wanted only Plans,
  and one run's edits were thrown away.
- 2026-10-01 · 0.71.1 · `land` · MAIN claimed that three changes landed with
  no proof run. Land had run `proof.sh` green for each, but a green
  automatic run leaves no line in the merge commit. The person re-ran four
  probes by hand.
- 2026-10-01 · 0.71.1 · `land` · an exit 7 message said "changes the proof
  adapter" when only probes changed.
- 2026-10-01 · 0.71.1 · `bash-guard` · `cd <scratch> && bun install
  >/dev/null` asked as a write in the primary tree. The redirect broke the
  reading of the `cd`. Fixed in 0.72.0, with a test.
- 2026-10-01 · 0.71.1 · `land` · an old flaky e2e test failed three lands
  with exit 6. The re-lands waited up to 1.5 hours for its fix.
- 2026-09-29 to 2026-10-01 · 0.70.1 · `coordinate` · MAIN ran the 0.70.1
  scripts in 250 of 250 calls, while its sessions moved to 0.71.1. The
  0.71.1 `coordinate.sh planned` found no watch and exited 0 with no
  event, in all 30 plan sessions. Each planner reported the signal as
  sent. MAIN wrote about 49 pollers of its own, and two hung when a
  planner renamed the slug. Nothing warned MAIN of the newer version.
- 2026-09-29 to 2026-10-01 · 0.70.1 · `coordinate` · no event follows
  `stopped` when the session finishes its report. MAIN wrote about 12
  waiters for it.
- 2026-09-29 to 2026-10-01 · 0.70.1 · `coordinate` · `finished` for the
  consolidate pass fired while its cuts were still unlanded. For the
  garden pass it came 10.5 minutes after the last land.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `coordinate` · two
  `landed` events named the same wrong commit. `worktree.sh` takes HEAD in
  the caller's directory, not the merge commit. MAIN relayed the wrong SHA
  once.
- 2026-09-29 to 2026-10-01 · 0.70.1 · `coordinate` · MAIN guessed a
  sign-off or grant state 5 times, and was wrong once for 8 minutes.
  `list` and `board` do not read `.hone-proof/` or `.hone-grant/`.
- 2026-09-29 to 2026-10-01 · 0.70.1 · `coordinate` · MAIN sent "go" and
  "land again" to sessions with `herdr agent prompt`. A relayed `! attest`
  with a leading space reached the session as text, and the sign-off
  waited 18 minutes.
- 2026-09-29 to 2026-10-01 · 0.70.1 · `coordinate` · `admit` ignored the
  predecessor that a Plan declared, twice. The run skill's Plan read
  stopped both runs before they claimed.
- 2026-09-29 to 2026-10-01 · 0.70.1 · `coordinate` · the person said early
  to accept all plans and grants. They still acted 22 times in run tabs in
  the first half, and gave 9 attests, 3 grants, and 6 prompt answers in
  the second. MAIN never offered `.hone-grant-auto`, and asked 4 questions
  the person had already answered.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · progress line · MAIN
  relayed no progress line in 280 messages. The coordinator tab shows
  none. A line shows only when a Bash call returns: a foreground
  land showed nothing for 4 to 10 minutes, once 57. A background verify's
  line came 4 to 19 minutes late.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · progress line · one run
  showed `verify ✓` after a red verify.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `worktree.sh land` · the
  land lock starved. A new verify took the lock ahead of a waiting land.
  One land hit exit 5 seven times over 2 hours 17 minutes, another four
  times over about 45 minutes. The first wave had about 8 exit-5 timeouts.
  Up to 7 runs ran at once.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `worktree.sh land` · land
  took the lock before the authority and proof gates. Waits of 9, 9, and
  36 minutes ended in exit 7 or exit 8, and one more cost 23 minutes.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `worktree.sh land` · a
  concurrent land emptied the shared `hone-land.log`, and one run lost the
  evidence for its exit 6.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `worktree.sh land` ·
  stopped at exit 8, then after the grant at exit 7. Land names the
  person's gates one at a time.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `gate` · `verify` writes
  no gate receipt. So the Stop gate ran `--all` again while the run only
  waited for the person, for 30 and 32 minutes. Two gates hit the 600-second
  hook timeout and failed open.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `gate` · picked `--all` on
  a fresh `hone/*` branch with no commits. The receipt then reported
  "already passed" before the change existed.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `gate`/`nag` · ran in
  every nested `/code-review` session. One review held the suite lock for
  3.7 minutes, and the nag told a reviewer to run `/hone:run`.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `gate` · blocked on a
  background subagent's red-green steps, 12 times in one run and 4 in
  another. Each distinct red counts on its own, so the cap of three never
  applied.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `gate`/`worktree.sh land`
  · the failure tail of a red suite showed only passing lines, twice.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · proof gate · a `*.test.ts`
  edit under `scripts/proof-probes/` asked for the change's own probe,
  which exited 3. The person signed two attests that recorded the exit 3.
  The message said the change "rewrites an existing probe", which was
  false.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · proof gate · 7 of 9 area
  moves changed only a path in a probe's comment, and each needed a proof
  run. 8 of 40 probe runs failed the same way on main, and the person
  signed them.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · proof gate · one run
  needed 3 attests for an unchanged probe, because main moved twice and
  the sign-off is pinned to the tip.
- 2026-09-28 to 2026-10-01 · 0.65.0 to 0.70.1 · herdr MAIN · relayed a
  SUB's probe output as fact and drafted the sign-off from it. The person
  signed stale output, and MAIN caught it before land. In the coordinated
  batch, MAIN relayed sign-off requests as the session's own claims and
  recommended signing. `land.md` asks for the verbatim output.
- 2026-09-21 to 2026-10-01 · mixed · `bash-guard` · denied a formatter run
  as writing a durable file, three times. Its target path was an
  unresolved variable. It also denied a read-only listing under
  `.hone-grant/triggers/` as a write into it. It denied a package-manager
  init or install in a scratchpad or worktree as writing its own files,
  four times. Fixed in 0.63.0 where the command sets the path itself. On
  0.70.1 to 0.71.1 both shapes asked again in worktrees. A formatter on an
  unresolved `$F` waited 97 minutes, 98 seconds, and 30 seconds, and the
  message said "primary tree". MAIN advised the person to answer No. `bun
  install --cwd <worktree>` waited 54 minutes, about 2 minutes, and once
  more. That shape still asks on 0.71.1.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `bash-guard` · a Python
  heredoc whose text held `git reset --keep` asked as a move of HEAD, for
  8.7 minutes. Still asks on 0.71.1.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `bash-guard` · `grep
  "chmod" scripts/proof.sh` asked as a change to a protected artifact, for
  2.5 minutes. Still asks on 0.71.1.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `bash-guard` · a `sed -i`
  on a Plan held `stryker.conf.json` in its expression. It asked as a
  change to a check config, for 11.3 minutes. Still asks on 0.71.1.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `guard` · rule 1b asked on
  a `stryker.conf.json` repoint that the Plan required, for 20 minutes.
- 2026-09-21 to 2026-10-01 · mixed · run loop · a session ran land again
  after an exit 9 or exit 6 with no word from the person, 5 times. Twice a
  Sonnet main session on 0.58.1 did it, once citing a memory file against
  `land.md`. On 0.70.1 to 0.71.1 three runs did it after exit 6, each
  citing a memory in the project. The run skill forbids it since 0.61.0.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `nag` · told MAIN, runs,
  and plan sessions that Plans are pending and to run `/hone:run`, 149
  times in MAIN alone. That advice is wrong for a coordinator.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `nag` · the area-size
  count included a generated `output.css`, 11,699 of 17,764 lines.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `plan` · the rule that
  `docs/` changes only at consolidate made two Plans that could not run,
  because a test checks that the docs cite `src` paths. The `plan-critic`
  caught both.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `plan` · a Plan slug sat
  under a gitignored directory. Only the planner caught it.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · `plan-critic` · approved 4
  explicitly delegated sketches by an exception that the prompt does not
  state. 5 of 15 Plans changed after APPROVE with no second check.
- 2026-09-29 to 2026-10-01 · 0.71.1 · `consolidate` · the global pass
  covered 17 of 32 merges. Its prompt names no base commit.
- 2026-09-29 to 2026-10-01 · 0.71.1 · `garden` · 3 of 4 cuts were test
  deletions. The skill reads a cut that keeps the suite green as dead
  code, so they skipped review. All 4 were safe on reading. A spike could
  not go, because the person's deny rule blocks `rm -rf`, and it sat on
  the board for about 10 hours.
- 2026-09-29 to 2026-10-01 · 0.70.1 to 0.71.1 · run loop · a flaky new
  test landed. A later land's exit 6 caught it. The run skill has no rule
  for an intermittent red in a test the change adds.
- 2026-10-01 · 0.70.1 · `coordinate` · MAIN agreed to answer permission
  prompts in the garden tab for the person. The skill says MAIN never
  answers for the person. No prompt followed.
- 2026-09-30 · 0.70.1 · `coordinate` · a stop that ended in text reached
  MAIN only when the person asked "Status?", 9 minutes later. About 10
  `quiet` events in the first night carried nothing new. The person asked
  for status 5 times in the batch.
- 2026-09-30 · 0.70.1 · `coordinate` · the harness stopped MAIN's
  background wait at its time limit 3 times, and 4 of MAIN's own pollers.
  Once MAIN asked the person to send any message to wake it.
- 2026-09-28 · 0.67.0 · `/hone:grant` · in auto mode, Claude Code handed
  the skill's shell block to the model. The `bash-guard` then denied the
  grant as the model's own. The person granted with a `!` line instead.
  Removed in 0.68.0.
- 2026-09-25 to 2026-09-28 · 0.59.0 to 0.65.0 · herdr MAIN · about 12
  times, MAIN ended its turn with no watch on a running SUB. 13 stops
  or lands reached MAIN only when the person asked for status. The worst
  lag was 7 h 54 min.
- 2026-09-25 to 2026-09-28 · 0.59.0 to 0.65.0 · herdr MAIN · 12 times, a
  SUB needed the person and got no notification. One proof-gate
  sign-off waited 7.5 hours.
- 2026-09-25 to 2026-09-28 · 0.59.0 to 0.65.0 · herdr MAIN · 6 of 6 MAINs
  replaced `herdr agent wait` with a home-made watcher. A harness memory
  says that the wait returns early. The watchers fired once only,
  waited for `blocked` and missed an `idle` gate stop, or read leftover
  shells as busy.
- 2026-09-27 to 2026-09-28 · 0.65.0 · `bash-guard` · held 3 of 3
  `herdr notification show` calls for approval. Their body text named a
  formatter command. The person waited 4, 28, and 12 minutes.
- 2026-09-27 · 0.65.0 · herdr MAIN · forwarded another MAIN's acceptance
  to a SUB that had stopped at a Plan precondition meant for the person.
- 2026-09-25 to 2026-09-26 · 0.59.0 to 0.63.0 · herdr MAIN · told a SUB
  to run `land` again after exit 6 with no word from the person, twice.
- 2026-09-21 to 2026-09-26 · 0.58.1 to 0.63.0 · `guard` · 5 of 6
  test-first denies were on fixture files under `src/`. The agent wrote a
  test for each fixture.
- 2026-09-21 to 2026-09-26 · 0.58.1 to 0.63.0 · run loop · a land that
  succeeded returned exit code 1 in 8 sessions, because the Bash call stood
  in the worktree that land removed.
- 2026-09-21 to 2026-09-26 · 0.58.1 to 0.63.0 · `bash-guard` · of 76 field
  asks, 41 still ask when replayed on 0.65. Shapes include a merge in a
  `mktemp` worktree and `dprint fmt` on a Plan.
- 2026-09-25 · 0.59.1 · `garden` · `skills/garden/SKILL.md` reads every land
  exit 6 as "the cut was unsafe," but since 0.59.1 a refused merge hook also
  exits 6. Fixed in 0.61.0.
- 2026-09-25 · 0.59.0 · `plan-critic`/`consolidate-critic` · both missed
  that a CLI upgrade had made a stated Decision false. The nested review
  caught it instead.
- 2026-09-25 · mixed · run loop · land's exit 9 reported a refused
  pre-merge-commit hook as a merge conflict, in three sessions. Fixed in 0.59.1.
- 2026-09-25 · 0.58.1 · `nag` · a "survived its landing" false alarm fired
  three times in one session. This happened while its worktree was still
  legitimately open, right after a rollback. Fixed in 0.62.0.
- 2026-09-25 · 0.58.1 · `dirty-guard` · blamed paths from another session's
  half-finished manual merge in the primary tree on two unrelated commands.
  Both agents correctly declined the hook's suggested restore. A fix in
  0.62.0 let a staged write through and was reverted in 0.62.1. Open.
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · land's post-merge checks in
  the primary tree read other sessions' untracked draft Plans, causing at
  least 6 spurious rollbacks. Fixed in 0.60.0.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `bash-guard` · a scratch
  `stryker.conf.json` for the mutation check matched the tracked-check-
  config rule. The ask did not name the file. Unattended runs stalled 7
  hours, 81 minutes, 69 and 12 minutes, and 40 minutes across four
  sessions. Fixed in 0.63.0, after a first fix in 0.62.0 was reverted.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `bash-guard` · the primary-branch-
  move ask fired 14 times, 3 right and 11 false. False shapes: a
  directory change into a scratch worktree, a path-scoped `git reset`,
  and a checkout addressed only by a shell variable. One false ask sat
  40 minutes. Fixed in 0.63.0 where the command sets the path itself. A
  directory that another command found still asks.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `gate` · the suite-lock block named
  "another session" as the holder, about 20 times. The real holder was
  the session's own land, or its background verify. The block skips the
  retry cap, so an agent looped on turns with no visible output. Fixed in 0.62.0.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `nag` · the broken-link check read
  `javascript:` and `data:` links inside inline code as real. It printed
  on every stop in every session. A doc over its line cap and a list of
  pending Plans also repeated on every stop, with no action taken. Fixed in 0.62.0.
- 2026-09-21 to 2026-09-25 · mixed · run loop · 10 of 23 finished runs
  printed fewer than 5 of the 6 step-start progress lines.
  `skills/run/SKILL.md` asks for one at the start and end of each step.
  Five runs went quiet for 30 to 50 minutes with no line at all.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `plan-critic` · approved a Plan
  whose Proof trailer needed a probe script keyed by the change's slug.
  No such script existed. This happened twice, and land then failed the
  proof gate both times. Fixed in 0.61.0: the critic checks the proof
  route.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `consolidate-critic` · proposed
  three cuts a person had to decline. They were: a required
  `MutationObserver`, a test and a sentence nested review later restored,
  and content outside the diff that another Plan had ring-fenced.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `plan-critic`/`consolidate-critic` ·
  verdict format drifted: a bolded verdict, a "Verdict:" prefix, prose
  after the verdict, a file list last. Clean on a small 0.59.0 sample,
  too small to call fixed.
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · land's authority gate (exit
  8) fired 3 times and caught nothing real. Twice it fired on SQLite's
  table-rewrite idiom, and once as a false alarm from the land rollback
  bug below. Partly addressed in 0.60.0: the refusal now quotes each
  destructive statement with its file.
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · land run from inside its
  own worktree exited 2 after a successful merge, three times. It also
  printed getcwd noise. `worktree.sh remove` also rejected a change name
  or a relative path, twice. Fixed in 0.60.0.
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · `/hone:plan` fired when
  the person had asked for a chat handoff instead ("No, don't plan").
  Addressed in 0.61.0: the plan skill fires only for a Plan.
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · a session created and
  landed an unplanned worktree after the person said "You do it."
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · the person twice asked
  the agent to speak plainly. Once was about a plan-skill blocking
  question, once about a run reply.
- 2026-09-22 · 0.58.1 · run loop · land's rollback `git reset --hard`
  dropped a concurrent Plan's own commit from main, twice. A branch cut
  from the dropped commit later caused a false exit 8. Fixed in 0.60.0.
- 2026-09-21 · 0.58.1 · `session-start` · one session's workflow-rule
  injection went missing. Right by design: the person had created the off
  marker ten seconds before that session started.
- not recorded · 0.58.1 · run loop · land's receipt named the wrong
  commit as the merge. It named a Plan commit made mid-suite, not the
  real merge. Fixed in 0.60.0.
- not recorded · 0.58.1 · `plan-critic` · took four rounds, about 17
  minutes, on a one-paragraph docs Plan. Each reject named a real
  contradiction, mostly introduced by the previous fix.
- not recorded · 0.58.1 · run loop · land's proof gate named a probe script
  for a change that had edited another change's probe. That script did
  not exist. Fixed in 0.60.0.

- 2026-08-20 to 2026-09-18 · mixed · `nag` · 314 lines telling the session
  that a template entry under the spike directory carries no date. The person
  moved the file to silence it.
- 2026-08-20 to 2026-09-18 · mixed · `nag` · 482 lines about one file two
  lines over its cap, over four weeks. Nobody ever acted on it.
- 2026-08-20 to 2026-09-18 · mixed · `nag` · 26 lines calling a markdown link
  broken. The link sat inside inline code, as an example of what a sanitizer
  strips.
- 2026-08-20 to 2026-09-18 · mixed · `gate` · 71 suite-lock blocks. Right by
  design, and not one of them reported a defect.
- 2026-08-20 to 2026-09-18 · mixed · `gate` · 5 unit blocks whose output tail
  showed application log noise. The agent re-ran the suite each time with its
  own filter.
- 2026-09-17 to 2026-09-18 · not recorded · `dirty-guard` · 30 blocks on
  read-only commands, across three sessions and two days. One file was
  already uncommitted before the sessions began.
- 2026-09-18 · not recorded · `dirty-guard` · the agent absorbed 27 of those
  blocks in one session. It never restored the file and never named the hook.
- 2026-08-21 to 2026-09-01 · 0.40.1 · `nag` · 437 lines of one finding that
  repeats on every stop. Only a person can clear it, and two people did.
- 2026-08-29 to 2026-08-30 · 0.40.1 · run loop · the harness permission
  classifier refused the prescribed re-run of land after a grant, in two
  sessions. The person ran the merge.
- 2026-08-28 · 0.47.0 · `bash-guard` · the agent reached for the flag that
  skips git hooks while amending in a worktree. Denied, and it complied.
- 2026-08-28 · 0.40.1 · `bash-guard` · a read of the config key that
  redirects git hooks was denied as sabotage. The agent lost the diagnosis it
  wanted.
- 2026-08-28 · 0.40.1 · `bash-guard` · a package manager invoked to print its
  help was denied as a writer of its own files.
- 2026-08-28 · not recorded · `bash-guard` · the sign-off helper escalation
  cost 31 minutes of waiting. Its reason named the protected-artifact rule
  instead of the sign-off rule.
- 2026-08-28 · not recorded · run loop · a grant stop cost a round trip. The
  exact command sat below the fold of a long report.
- 2026-08-28 · 0.40.1 · `gate` · a red unit suite caught at a turn end.
  Right, and the session went green later.
- 2026-08-28 · 0.40.1 · `plan-critic` · approve on a Plan whose negative
  claim about a third-party tool rested on a proxy signal in a config file.
  Case: `plan-critic/tool-negative-from-config`.
- 2026-08-28 · 0.40.1 · `plan-critic` · reject whose only finding was a
  number in motivating prose that no build step reads. One extra round.
  Case: `optimize/cases/plan-critic/stale-count-in-motive`, removed on
  2026-10-01. Git keeps it.
- 2026-08-24 to 2026-08-28 · mixed · `bash-guard` · 10 asks on a formatter
  run scoped to the plan directory, which the perimeter exempts.
- 2026-08-21 to 2026-08-28 · mixed · `bash-guard` · 11 asks on a command that
  changed directory out of the primary tree before it wrote anything.
- 2026-08-25 to 2026-08-28 · mixed · `bash-guard` · 4 asks on a copy. A
  protected file was its source, and a scratch file was its target.
- 2026-08-24 to 2026-08-28 · mixed · `consolidate-critic` · 2 cuts aimed at
  prose outside the change's diff. The author declined both.
- 2026-08-27 · not recorded · `consolidate-critic` · 2 cuts that contradicted
  the Plan's stated stance. One weakened a safety parameter the Plan had
  flagged.
- 2026-08-27 · 0.40.1 · `nag` · a live Plan reported as landed, because an
  older change had reused the same slug.
- 2026-08-26 · 0.40.1 · `dirty-guard` · caught a write into the primary tree
  after the shell working directory had silently reset. Right, and the hole
  the hook exists for.
- 2026-08-26 · 0.40.1 · `consolidate-critic` · proposed deleting a spike
  because its forward pointer dangled. hone's own lifecycle guarantees that
  pointer will dangle.
  Case:
  `optimize/cases/consolidate-critic/spike-pointer-to-deleted-plan`,
  removed on 2026-10-01. Git keeps it.
- 2026-08-26 · not recorded · `consolidate-critic` · proposed cutting a
  browser-level test as redundant with a server-level one. Two layers, one
  proposition.
  Case: `consolidate-critic/same-claim-two-layers`.
- 2026-08-24 to 2026-08-26 · mixed · `guard` · 4 denies of a new module with
  no test. All right, and the agent wrote the test first each time.
- 2026-08-25 · not recorded · `guard` · denied a durable docs edit in the
  primary tree. The person set and cleared the off marker twice that session.
- 2026-08-25 · 0.40.1 · `plan-critic` · approve on a Plan whose citations all
  checked out. The rule it derived from them was too general, and it landed
  in a durable document.
  Case: `plan-critic/invariant-overgeneralised`.
- 2026-08-25 · 0.40.1 · run loop · hone's own recommended deny rules blocked
  a Plan-sanctioned edit to a project config file, with no sanctioned route.
  The person patched by hand after three failed attempts.
- 2026-08-25 · 0.40.1 · run loop · the proof gate demanded a full
  real-environment proof for a comment rewrap in a protected script.
- 2026-08-25 · not recorded · run loop · two stops handed the person a
  prepared patch. The change's own subject sat inside the deny perimeter.
- 2026-08-25 · not recorded · `gate` · 3 blocks from a check tool. It failed
  on a temporary directory that a mutation-testing run had left behind.
- 2026-08-25 · not recorded · `consolidate-critic` · a clean verdict claimed
  a worktree was gone. It read the diff and the Plan, never the filesystem.
  Case: `consolidate-critic/ordered-deletion-not-in-diff`.
- 2026-08-25 · 0.40.1 · `bash-guard` · the agent reached for the flag that
  skips git hooks inside a land retry loop. Denied, and it re-ran without it.
- 2026-08-24 · 0.40.1 · `bash-guard` · a command put a hooks-path override in
  front of a commit. Denied, and the model withdrew it itself.
- 2026-08-24 · not recorded · `bash-guard` · a read-only stash listing
  escalated as a move of the checked-out commit. The notification that told
  the person about the block escalated too.
- 2026-08-20 · not recorded · `plan-critic` · approve on a Plan that stripped
  a metadata block from every input. For one producer that block held the
  only copy of the data.
  Case: `plan-critic/indexer-strips-only-copy`.
