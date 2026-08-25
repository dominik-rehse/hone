# `worktree.sh land`: exit codes and what each one means

Background for step 6 of `run`. `SKILL.md` carries the compact table. Read this
when land returns something other than 0, before you act on it.

`land` takes the **land lock**, so it is safe even when another `run` is landing
into the same primary tree at the same time. It waits its turn instead of
interleaving. Under the lock it merges `--no-ff`, **re-runs the whole suite** in
the primary tree, and on green removes the worktree and deletes the branch. The
confirmation is the suite, not the merge succeeding.

## 0: landed and green

The merge is in, the suite passed in the primary tree, the worktree and branch
are gone. Confirm to the user what landed, the Decisions and Notes written, and
what was deleted.

## 6: the merge regressed the trunk

`land` rolled the merge back, so the primary tree is left green, and kept the
worktree as evidence. This is stop-point 1 surfacing at land: the change passed
in isolation but not against what else has landed since. **Stop and escalate.**

Read the message first: it names what failed (the suite, `typecheck`, `lint`,
or `setup-tree`). A `setup-tree` red means the install step failed in the
primary tree, not that the change regressed anything. One more case wears this
exit. Take a project with **no** `setup-tree.sh`, and a land that changed a
lockfile. There, the suite red can be the stale primary-tree install rather
than the change. The tell is a lockfile in the branch diff plus a
missing-module error in the land log. Shipping a `scripts/setup-tree.sh` is
the durable fix.

## 9: merge conflict

Aborted, tree restored. Under `--all` this means the independence check missed an
overlap: fold this change in serially and flag it for a Decision-level look. Do
not force the merge.

## 5: lock timeout

Another session held the land lock (a land or a full-suite run) past the
timeout. Nothing happened to the trunk. Wait for that run to finish, then
re-run land. Never work around the lock.

## 2: usage or repo-state error

The branch does not exist, the primary tree is on a detached HEAD, or the
invocation was malformed. Nothing was merged. Read the stderr line. Fix the
state (from the primary tree) rather than retrying blindly.

## 7: the proof gate

The change needs real-environment proof, and that proof is missing. Three things
ask for it. A `Proof: real-environment` trailer on a branch commit asks for it.
So does a committed `.hone-proof-always` marker, which gates every change, with
a trailer or without one. So does the change rewriting the proof harness: any
edit to `scripts/proof.sh`, or an edit to a probe under
`scripts/proof-probes/` that already exists. That third gate fires on the file
change itself. It needs no trailer and no marker. Adding a *new* probe does
not fire it.

Two things discharge it. A green `scripts/proof.sh` discharges it, and so does
a `.hone-proof/<change>` sign-off naming the current branch tip. land runs the
primary tree's reviewed copy of the adapter, from the worktree, so it reaches
the code under test. A proof.sh the change itself adds does not count until it
lands. A sign-off written for an earlier commit stops counting, by design: it
must not outlive the code it vouched for.

The merge did not happen and the worktree is kept. Run the check the refusal
names, record what you ran with `worktree.sh attest <change> "<what you ran and
what it printed>"`, and land again. Where the declared check is outside your
reach, **stop and escalate** instead, and leave the sign-off to the human. A
sign-off naming a check nobody ran reads as evidence in history and carries
none.

Read the message to see which of the five refusals fired:

- *No proof yet.* Where the trailer declared a check, the message prints it.
  The message then prints the full `worktree.sh attest` command with its path.
  The human runs the check in their own terminal and records it with that
  command.
- *A stale sign-off.* The message names the tip the sign-off does not cover,
  and prints the same attest command.
- *The adapter failed.* The message points at the adapter output above it. Fix
  the change, then land again. This refusal prints no attest command, because
  the real environment refused the change.
- *The marker without an adapter.* The message asks the human to add
  `scripts/proof.sh`, and prints no attest command. Never remove
  `.hone-proof-always` to get past it. The marker is project policy, and both
  guards protect it.
- *The change edits the adapter.* The message names the file change as the
  reason, because the branch declared nothing. It prints the same attest
  command.

One case has no automatic route. Where the change itself rewrites the proof
harness, land runs no adapter for it, because the copy land holds is the copy
the change replaces. Run `bash scripts/proof.sh <change>` from the worktree
yourself, read its output, and attest with what it printed. That run is a real
check of the branch's own adapter, so the sign-off it produces is honest.

Rewriting the harness means one of two diffs: any edit to `scripts/proof.sh`,
or an edit to a probe under `scripts/proof-probes/` that already exists. A
change that only *adds* a new probe is not rewriting the harness. It is
writing its own check, the way it writes its own tests, and the adapter that
will judge it is untouched. So an added probe lands on the ordinary route, and
`/code-review` reads it in the same diff.

You may author a harness change in the worktree, and you should. The gate is
what holds it, not a ban on writing it. land reads the diff, so the gate fires
on any branch that rewrites those files. A branch that declares no trailer gets
the same refusal as one that declares it.

Write the sign-off with `worktree.sh attest` and nothing else. A file write or
a shell redirect into `.hone-proof/` skips the signer stamp, the commit
binding, and the placeholder check, and both guards deny it. Never paste a
commit id into a file to satisfy the check: the check is the run, not the
file.

## 8: the authority gate

`land` classified the diff as an
*irreversible* change (destructive SQL, a `db/` deletion, a
`.hone-irreversible-paths` match) and found no `.hone-grant/<change>`.

The merge did not happen and the worktree is kept. The refusal prints the
signals that fired, a diffstat, and the command to read the whole diff. Read
that diff. Then decide one of two things.

If the change is what the Plan asked for, record the authorization with
`worktree.sh grant <change> "who/why"`, then land again. The exit-8 message
prints the full command with its path. The text lands in the merge commit
body, so it is the only record a reader gets a year from now. Name what is
irreversible, and why it is right anyway: "drops orders.legacy_ref, unused
since the 0.9 migration, per the Plan". Never "approved" or "ok".

If the diff does something the Plan never asked for, that is not a grant to
write. **Stop and escalate.** An irreversible change nobody planned is exactly
the case this gate exists for.

Write the grant with `worktree.sh grant` and nothing else. The guard and
bash-guard deny the file and shell routes into `.hone-grant/`, because the
helper is what stamps the signer.

## Never work around a non-zero exit

Never merge by hand, and never move the primary tree's HEAD
(`git checkout`/`switch`/`stash`/`reset`) to investigate. That races every other
session sharing the tree, and the `bash-guard` will stop you. The primary tree
stays on the trunk as a merge target. Do any investigation in a throwaway
`git worktree add --detach` scratch tree.
