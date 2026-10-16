# Spike: what the open-questions folder holds in real use

**Date:** 2026-10-16 · **Status:** frozen. Written once, never maintained
against the code.

## Question

Does `docs/open-questions/` hold only bets that running code can settle, as
`docs/model.md` defined it at 0.81.1?

## What I did

I read the first lines of every file under `docs/open-questions/` in the four
repositories that run hone, and each repository's `docs/roadmap.md`. I sorted
each file by what must happen before anyone can act on it. I read the first
lines only, so a few files could fit more than one group.

## Finding

Two repositories used the folder as defined. Of their 21 files, 20 were bets
for the real environment, and one was a flaky test.

The largest repository held 52 files:

- 27 bets for the real environment: timings, memory limits, API behavior.
- 9 known or likely defects that an in-repo test can reproduce. Some files
  said "reproduce it with a unit test" or "verified by hand".
- 9 security gaps that wait for a policy call.
- 6 product questions for the owner.
- 1 wait for an upstream release.

In the fourth repository, most of the 7 files were design or security calls
for the owner. Its roadmap cited them as the next work, in order.

The cause was in hone's own prose. `run` filed a declined review finding as
an open question, and `garden` filed every call for a person there. Both had
no other per-file place, and parallel runs must not edit the roadmap. The
bets hid the owner's decisions, and `worktree.sh attention` did not show
them.

The largest roadmap had grown its own sections by kind (bugs, features,
performance, structure). One item was in the roadmap and in the folder.

## Where it landed

`docs/issues/` with its `Type:` and `Waits on:` lines, in
[`reference.md`](../reference.md) under *Project layout*.
