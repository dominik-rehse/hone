# `worktree.sh land`: exit codes and what each one means

Background for step 6 of `run`. `SKILL.md` carries the compact table; read this
when land returns something other than 0, before you act on it.

`land` takes the **land lock**, so it is safe even when another `run` is landing
into the same primary tree at the same time: it waits its turn instead of
interleaving. Under the lock it merges `--no-ff`, **re-runs the whole suite** in
the primary tree, and on green removes the worktree and deletes the branch. The
confirmation is the suite, not the merge succeeding.

## 0 — landed and green

The merge is in, the suite passed in the primary tree, the worktree and branch
are gone. Confirm to the user what landed, the Decisions and Notes written, and
what was deleted.

## 6 — the merge regressed the trunk

`land` rolled the merge back, so the primary tree is left green, and kept the
worktree as evidence. This is stop-point 1 surfacing at land: the change passed
in isolation but not against what else has landed since. **Stop and escalate.**

## 9 — merge conflict

Aborted, tree restored. Under `--all` this means the independence check missed an
overlap: fold this change in serially and flag it for a Decision-level look. Do
not force the merge.

## 5 — lock timeout

Another session held the land lock (a land or a full-suite run) past the
timeout. Nothing happened to the trunk. Wait for that run to finish, then
re-run land; never work around the lock.

## 2 — usage or repo-state error

The branch does not exist, the primary tree is on a detached HEAD, or the
invocation was malformed. Nothing was merged. Read the stderr line; fix the
state (from the primary tree) rather than retrying blindly.

## 7 — the proof gate

The change's commit body carries
`Proof: real-environment` and the proof is still missing: no green
`scripts/proof.sh` (invoked as `proof.sh <change>` from the worktree, so it can
reach the code under test), and no `.hone-proof/<change>` sign-off naming the
current branch tip. A sign-off written for an earlier commit stops counting, by
design: it must not outlive the code it vouched for.

The merge did not happen and the worktree is kept. **Stop and escalate.** The
real-environment check is outside the loop's boundary: the human runs the journey
or canary and records it, in their own terminal, with
`worktree.sh attest <change> "what they ran"`. Never sign it off yourself, never
run `attest`, and never write the commit id into a sign-off file to satisfy the
check — the bash-guard denies all of these.

## 8 — the authority gate

`land` classified the diff as an
*irreversible* change (destructive SQL, a `db/` deletion, a
`.hone-irreversible-paths` match) and found no `.hone-grant/<change>`.

The merge did not happen and the worktree is kept. **Stop and escalate.** This
needs the human's scoped grant, recorded in their own terminal with
`worktree.sh grant <change> "who/why"`. Never create the grant yourself and
never run `grant` — authority is theirs to give, and the bash-guard denies both
routes.

## Never work around a non-zero exit

Never merge by hand, and never move the primary tree's HEAD
(`git checkout`/`switch`/`stash`/`reset`) to investigate: that races every other
session sharing the tree, and the `bash-guard` will stop you. The primary tree
stays on the trunk as a merge target; do any investigation in a throwaway
`git worktree add --detach` scratch tree.
