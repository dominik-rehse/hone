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

## 2 — merge conflict

Aborted, tree restored. Under `--all` this means the independence check missed an
overlap: fold this change in serially and flag it for a Decision-level look. Do
not force the merge.

## 7 — the proof gate

On by default; `.hone-proof-off` disables it. The change's commit body carries
`Proof: real-environment` and the proof is still missing: no green
`scripts/proof.sh` (invoked as `proof.sh <change>` from the worktree, so it can
reach the code under test), and no `.hone-proof/<change>` sign-off naming the
current branch tip. A sign-off written for an earlier commit no longer discharges
the change, by design: an attestation must not outlive the code it attested.

The merge did not happen and the worktree is kept. **Stop and escalate.** The
real-environment check is outside the loop's boundary: the human runs the journey
or canary and signs it off. Never sign it off yourself, and never write the commit
id into a sign-off file to satisfy the check.

## 8 — the authority gate

On by default; `.hone-authority-off` disables it. `land` classified the diff as an
*irreversible* change (destructive SQL, a `db/` deletion, a
`.hone-consequential-paths` match) and found no `.hone-grant/<change>`.

The merge did not happen and the worktree is kept. **Stop and escalate.** This
needs the human's scoped grant. Never create the grant yourself: authority is
theirs to give.

## Never work around a non-zero exit

Never merge by hand, and never move the primary tree's HEAD
(`git checkout`/`switch`/`stash`/`reset`) to investigate: that races every other
session sharing the tree, and the `bash-guard` will stop you. The primary tree
stays on the trunk as a merge target; do any investigation in a throwaway
`git worktree add --detach` scratch tree.
