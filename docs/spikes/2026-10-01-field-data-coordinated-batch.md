# Spike: field data from a coordinated batch

**Date:** 2026-10-01 · **Status:** frozen. Written once, never maintained
against the code.

## Question

A MAIN session ran `/hone:coordinate` under herdr and drove about 34 Plans
through plan, run, consolidate, and garden sessions in one night and a
day. The person said early on that MAIN should not come back to them,
and that they accepted all plans and grants. How did hone perform in that
batch? Where did the time go, and what broke?

## Method

I read the Claude Code transcripts of one private consumer repository,
from 2026-09-29 20:01Z to 2026-10-01 04:19Z. There were 105 sessions:

- 1 MAIN session, the coordinator.
- 30 plan sessions and 34 run sessions.
- 1 global consolidate pass and 1 garden pass.
- about 34 nested `/code-review` sessions, started by the runs.
- 5 side sessions.

MAIN called the cached 0.70.1 scripts for the whole batch, in 250 of 250
calls of `coordinate.sh`. The other sessions ran 0.70.1 until about
21:40Z on 2026-09-29, and 0.71.1 after that.

Nine agents read the transcripts by area. I checked the main claims about
hone's code against the source at 0.71.1. Where a claim names a line of
code, I read that line. I replayed four guard asks through the 0.71.1
`bash-guard`, and all four still ask. A follow-up batch started
at 05:01Z on 2026-10-01, and this note does not cover it.

The limits are the usual ones. This is one repository, one person, and
about 32 hours. The counts come from reading by eye, so read each one as
a lower bound.

## Outcome

38 changes landed: 32 batch Plans, 2 consolidate cuts, and 4 garden cuts.
No session sat stopped at the end. No red change reached main. Most
of the wall time went to three things:

- the person's latency at sign-offs, 5 to 6 hours twice overnight.
- waits on the suite lock.
- guard asks on safe commands.

## Results by area

### Communication between MAIN and its sessions

The 0.69.0 ticker and wait did their main job. `landed` and `stopped`
events reached MAIN within seconds. After a restart at 02:59Z, MAIN
rebuilt its state in 37 seconds. Compared with
[the 2026-09-28 note](2026-09-28-main-tracking-of-subs.md), where 13 stops
reached MAIN only when the person asked, this batch had one such stop.
It was at 09:12Z on 2026-09-30 and surfaced at 09:21Z, when the person
asked "Status?". That is better, and not solved.

What still went wrong:

- **Version skew.** MAIN ran 0.70.1 scripts while its sessions ran
  0.71.1. In 0.70.1, `start plan` registers no watch. In 0.71.1,
  `coordinate.sh planned` returns 0 with no event and no message when it
  finds no watched plan session. So the signal did nothing in all 30 plan
  sessions, and each planner reported that it had sent it. MAIN made up
  for it with about 49 pollers of its own that waited for the Plan file in
  git. Two of them hung, because the planner had renamed the slug. Nothing
  warns a running MAIN that a newer version is installed. MAIN moved to
  0.71.1 only at 07:26Z on 2026-10-01.
- **Silent stops.** A stop that ends in text reaches MAIN only through
  the `quiet` event, after 600 seconds idle. About 10 `quiet` events in
  the first night carried nothing new, and each raised a herdr
  notification.
- **No event for a finished report.** After `stopped`, MAIN gets no event
  when the session finishes its report. MAIN wrote about 12 waiters for it.
- **`finished` too early or too late.** For consolidate,
  `coord_pass_finished` returns true at once, so `finished` fired while the
  cuts were still unlanded. For garden, `finished` came 10.5 minutes after
  the last land, because it waits for `quiet`.
- **A wrong SHA in `landed`.** After land, `worktree.sh` takes the short
  SHA of HEAD in the caller's directory, not the merge commit. Two events
  named the same wrong commit. MAIN relayed it once before it checked.
- **The background wait died.** The harness stopped MAIN's wait at its
  limit 3 times on 2026-09-30, and 4 of MAIN's pollers the same way. Once
  MAIN asked the person to "send me any message" to wake it. The skill
  names no limit for the wait.
- **No path from MAIN to a session.** MAIN sent "go" and "land again" with
  `herdr agent prompt`. A relayed `! attest` with a leading space reached
  the session as text, and the sign-off waited 18 minutes.
- **Guessed state.** MAIN guessed a sign-off or grant state 5 times,
  and was wrong once for 8 minutes. `list` and `board` do not read
  `.hone-proof/` or `.hone-grant/`.
- **Early starts.** `admit` does not read the predecessor that a Plan
  declares. Two runs started before their predecessor landed. The run
  skill's Plan read stopped both before they claimed anything.
- **Person prods.** The person asked MAIN for status 5 times, and nudged
  a run tab with "land again" about 5 times.

### Suite lock and gate under parallel runs

Up to 7 runs ran at once, and `coordinate` sets no cap.

- **Lock starvation.** `flock -w` is not a queue. A new verify can take
  the lock ahead of a land that waits. One land hit exit 5 seven times
  over 2 hours 17 minutes. Another hit it four times over about 45
  minutes. The first wave alone had about 8 exit-5 timeouts. Agents found
  `HONE_LAND_LOCK_TIMEOUT` by reading the script.
- **Lock before the checks.** `land` takes the lock before the authority
  gate and the proof gate. Three lands waited 9, 9, and 36 minutes only to
  print exit 7 or exit 8. One more waited 23 minutes.
- **The Stop gate repeats verify.** `verify` writes no gate receipt. So
  at the turn's end the gate runs `--all` again while the session only
  waits for the person. That cost 30 and 32 minutes in two runs. Two gates
  hit the 600-second hook timeout and failed open. A side session that the
  person asked about the slow gate blamed the project's e2e tier instead.
- **A receipt for no change.** On a fresh `hone/*` branch with no commits,
  the gate picks `--all`. The receipt key is the version and the branch,
  and the tree is never compared. So a later stop reports "already passed"
  before the change exists. Land still re-verifies, so the cost is time
  and a false line.
- **Hooks in nested reviews.** The nested `/code-review` sessions ran
  hone's Stop hooks. The gate and the nag fired in all of them. One review
  held the suite lock for 3.7 minutes. The nag told a reviewer to run
  `/hone:run`.
- **Blocks on a background subagent.** The Stop gate blocked on a
  background subagent's red-green steps, 12 times in one run and 4 in
  another. The cap of three counts one signature, so distinct reds pass it.
- **One shared land log.** Each land empties `hone-land.log` when it
  starts. A concurrent land erased one run's evidence for its exit 6.
- **Tails that show no failure.** Twice the tail of a red suite in a land
  or gate message showed only passing lines.
- **A wrong progress line.** One run showed `verify ✓` after a red verify.

### Proof gate and sign-offs

- **A test file read as a probe.** A `*.test.ts` edit under
  `scripts/proof-probes/` maps to the change's own command in
  `land_proof_bootstrap`. That command exited 3 in the project's
  `proof.sh`. Twice the person signed an attest that recorded "proof.sh
  exit 3". The message also said that the change "rewrites an existing
  probe", which was false.
- **Comment-only edits arm the gate.** 7 of 9 area moves changed only a
  path in a probe's comment, and each needed a proof run. 8 of 40 probe
  runs failed the same way on main, and the person signed them anyway.
- **A sign-off pinned to the tip.** One run needed 3 attests for an
  unchanged probe, because main moved twice.
- **One gate at a time.** One land stopped at exit 8, and after the grant
  stopped again at exit 7.
- **Paraphrased relays.** MAIN relayed sign-off requests as the session's
  own first-person claims, and recommended signing. `land.md` asks for
  the verbatim output.
- **An open question.** At 08:17Z on 2026-10-01, MAIN claimed that three
  changes had landed with no proof run on the box. An added probe does not
  open the bootstrap gate, by design. Whether land ran those probes was
  not checked.

### Guard false asks

Each ask stops an unattended run until the person answers.

| Shape | Hook and rule | Wait | Replayed on 0.71.1 |
|---|---|---|---|
| Formatter on an unresolved `$F` in a worktree | `bash-guard`, rule 5 | 97 min, 98 s, 30 s | not replayed |
| `bun install --cwd <worktree>` | `bash-guard`, rule 4 | 54 min, about 2 min, one more | still asks |
| Python heredoc whose text holds `git reset --keep` | `bash-guard` | 8.7 min | still asks |
| `grep "chmod" scripts/proof.sh` | `bash-guard` | 2.5 min | still asks |
| `sed -i` on a Plan, with `stryker.conf.json` in the expression | `bash-guard` | 11.3 min | still asks |
| A `stryker.conf.json` repoint that the Plan required | `guard`, rule 1b | 20 min | not replayed |

The 97-minute ask said "primary tree" for a command in a worktree. MAIN
advised the person to answer No to a safe command. The `bun` ask said
"run it in a worktree", and the command already did. The 0.63.0 fixes
covered some of these shapes only where the command sets its path itself.

### Delegation

The person's "I accept all plans and grants" had no channel in hone. In
the first half of the batch the person still acted 22 times in run tabs.
In the second half they gave 9 attests, 3 grants, and 6 answers to
prompts. MAIN never offered `.hone-grant-auto`. It asked 4 questions the
person had already answered. At 03:33Z MAIN agreed to answer permission
prompts in the garden tab for the person. The coordinate skill says that
MAIN never answers for the person. No prompt followed. Three runs ran
`land` again after exit 6. They cited a memory in the project, against
`land.md`.

### Nag

The nag told MAIN "N Plan(s) pending run in .plans/. Do: run /hone:run",
149 hook messages over the batch. That advice is wrong for a coordinator.
It also reached runs and plan sessions. MAIN learned to filter it out.
The area-size count included a generated `output.css`: 11,699 of 17,764
lines.

### Planning, consolidate, and garden

- `rules/workflow.md` says that `docs/` is written only at consolidate. Two
  Plans could not run as written, because a test checks that the docs cite
  `src` paths. The `plan-critic` caught both.
- A Plan slug sat under a gitignored directory. Only the planner caught it.
- Garden could not delete a spike under `docs/spikes/`, because the
  person's own deny rule blocks `rm -rf`. It sat on the board for about 10 hours.
- The `plan-critic` approved 4 explicitly delegated sketches by an
  exception that no prompt states. 5 of 15 Plans changed after APPROVE
  with no second check.
- The global consolidate pass covered 17 of 32 merges. Its prompt names
  no base commit.
- Garden cut 4 things. 3 were test deletions, and the skill reads "a
  deletion that keeps the suite green was dead". That proves nothing for a
  test, and those cuts skipped review. All 4 were safe on reading.
- A flaky new test landed. A later land's exit 6 caught it. The run skill
  has no rule for an intermittent red in a test the change adds.

### The progress line

The mechanism works. Every `worktree.sh` step printed a line in all 34
runs. Three things limit it:

- MAIN relayed none of the runs' progress lines, 0 of 280 messages, and
  the coordinator tab shows none.
- The line shows only when a Bash call returns. A foreground land's
  `land ...` line never shows while it runs, for 4 to 10 minutes and
  once 57 minutes. A background verify's line shows 4 to 19 minutes late.
- It is a message in the scrollback, not a fixed bar, so it scrolls away.

## What worked

- Every one of the 9 rejects of the `plan-critic` named a real defect. It
  also found collisions between Plans drafted in parallel.
- The nested `/code-review` found a real bug in every run. Once it found
  a coverage loss that three critics had missed.
- Land's exit 6 on the merge kept main green every time.
- The run skill's predecessor check stopped both early starts with no side
  effect.
- `landed` and `stopped` reached MAIN within seconds.
- The `watch` Stop hook armed the wait again each time MAIN needed it.

## What follows

The batch landed everything, and kept main green. The cost was time and
the person's attention. Most of that cost had three sources. The first
is the messages between MAIN and its sessions. The second is the suite
lock under parallel runs. The third is asks that a person had to clear. The open items are in
[the roadmap](../roadmap.md), and the incidents are in
[the field log](../field-log.md).
