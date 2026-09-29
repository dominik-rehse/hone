# Spike: what herdr's agent wait and state fields tell a watcher

**Date:** 2026-09-29 · **Status:** frozen. Written once, never maintained
against the code.

## Question

A harness memory in a consumer repository said that `herdr agent wait`
returns early, and six MAINs wrote their own watchers because of it
([the 2026-09-28 note](2026-09-28-main-tracking-of-subs.md)). Is that true
on herdr 0.9.2, and which signal can one hone watcher use instead? And
does a detached process outlive the Bash call that started it?

## What I did

On herdr 0.9.2 (client and server), I opened a tab with a plain shell and
ran `sleep 900` in it, so that herdr keeps an agent there. I then set the
pane's agent state by hand with `herdr pane report-agent`, and read it with
`herdr agent get` and `herdr agent wait`. Without the foreground `sleep`,
herdr 0.9.2 clears a self-reported agent at once, because the pane is back
at an idle shell.

For the second question, one Bash call ran `setsid -f sleep 433`, and a
later Bash call looked for the process. The auto-mode classifier refused a
test from a nested headless Claude Code session. So I did not test whether
the process outlives the whole session.

## Finding

- `agent wait` with no `--until` returned in 0.1 s on an agent that was
  already `idle`. The herdr docs say so. The wait returns at once when the
  status already matches. The default set is `idle`, `done`, and
  `blocked`. So the memory was half right. The wait has no timeout of its
  own, but a SUB that sits idle at a gate satisfies it at once, and a loop
  over it spins.
- `agent wait --until working` waited, and exited 1 at its timeout.
- `state_change_seq` rose by one on each state change. I read 12, 13, 14,
  16, 17, and 18, and did not read 15. A watcher that compares it between
  two reads sees every change, whatever the state.
- `completion_seq` appeared when a `working` agent went idle, and herdr
  then reported the state as `done`. A change from `blocked` to idle also
  set it.
- The `setsid -f` process was alive in the next Bash call.

## Where it landed

`scripts/coordinate.sh` in 0.69.0: one ticker polls `herdr agent get` and
compares `state_change_seq`, and the watch hook starts the ticker again
when it died. So the design does not depend on the part I could not test.
The run skill's `references/herdr.md` tells MAIN never to poll with
`herdr agent wait`.
