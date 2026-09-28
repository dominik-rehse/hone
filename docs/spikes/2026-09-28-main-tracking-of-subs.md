# Spike: how closely MAIN tracks its SUB sessions

**Date:** 2026-09-28 · **Status:** frozen. Written once, never maintained
against the code.

## Question

Under herdr, a MAIN session starts one SUB session per Plan and watches
them. The maintainer had the impression that MAIN does not always keep
close track of its SUBs. Is that true, and why?

## Method

I read the transcripts of 8 MAIN sessions in two private consumer
repositories, from 2026-08-29 to 2026-09-28. The hone versions were 0.47.0
and 0.59.0 to 0.65.0. One session ended 5 minutes after its first SUB
started, so I did not judge it. Three agents read the other 7 against
`skills/run/references/herdr.md`. They took each SUB's stop time from the
SUB's own transcript. They took MAIN's detection time from MAIN's
transcript.

Three of the 7 did not start through `/hone:run --all`. The person asked
in chat to run Plans in herdr panes, and those MAINs read little or none
of `herdr.md`. Each count below is a lower bound, from reading by eye.

## Results

One session tracked well: the 0.47.0 run of 2026-08-29. It used
`herdr agent wait` in the background for every SUB. Its largest lag was
3.5 minutes. The 6 later sessions, in the other repository, never used
`herdr agent wait`. The reason is a harness memory in that repository,
dated 2026-08-26. It says that the wait returned early with a timeout
error, and that a wait on a settled agent returns at once. I did not
verify that claim. The installed `herdr agent wait --help` says that the
wait has no limit when it gets no `--timeout`.

Each of those 6 MAINs wrote its own polling watcher instead. The counts
across the 6:

- MAIN ended its turn with a SUB running and no watch armed: about 12.
- A stop or a land reached MAIN only when the person asked for status:
  13. The worst lags were 7 h 40 min and 7 h 54 min, overnight.
- A SUB needed the person, and MAIN sent no `herdr notification show`: 12.
  One proof-gate sign-off waited 7.5 hours.
- The bash-guard held a notification, because its body text named a
  formatter command: 3 of the 3 that one MAIN sent. The person waited 4,
  28, and 12 minutes.
- MAIN told a SUB to run `land` again after exit 6 with no word from the
  person: 2. A third was partly authorized by "intervene where necessary".
  One SUB had written that the skill forbids the retry.
- MAIN relayed a SUB's screen as fact and drafted a sign-off command from
  it: 1. The person signed stale probe output. MAIN caught it before land.
- MAIN reworded a command after a guard refused it: 2.

The home-made watchers failed in five ways:

- It fired once and was not armed again.
- It waited for `blocked` only, and a gate stop leaves the SUB `idle`: 2
  sessions. One SUB sat unseen at the proof gate when this note was
  written.
- It counted leftover background shells on the SUB's screen as busy.
- It had a syntax error and never fired.
- Claude Code killed it for low memory, and MAIN did not start it again.

## Two MAINs at once

On 2026-09-27 and 2026-09-28, two MAINs ran in one repository at the same
time. hone checks overlap only within one MAIN's set of Plans, and a
claim covers only the same change. The two MAINs coordinated by
themselves over Claude Code's cross-session messages. They exchanged
rules, file lists, and holds on queued Plans. hone does not ask for this.

A message from the other MAIN once woke a MAIN that had no watch armed.
The agents found no conflict between the two sets. Once, a MAIN forwarded
the other MAIN's acceptance to a SUB that had stopped at a Plan
precondition meant for the person. The SUB then went on.

## What follows

- The SUB knows the moment it stops at a gate. Only MAIN sends the
  notification today. A notification that `worktree.sh land` sends by
  itself needs no MAIN to be awake.
- A MAIN needs one watcher that works. Each MAIN writing its own gives a
  new set of bugs each time.
- A message between MAINs may wake a session or ask for a hold. It must
  not answer a stop that belongs to a person, and it must not count as
  proof of a land.

The open items are in `docs/roadmap.md`, and the incidents are in
`docs/field-log.md`.
