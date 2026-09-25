# `worktree.sh land`: exit codes and what each one means

Background for step 6 of `run`. `SKILL.md` carries the compact table. Read this
when land returns something other than 0, before you act on it.

`land` takes the **land lock**, so it is safe even when another `run` is landing
into the same primary tree at the same time. It waits its turn instead of
interleaving. Under the lock it builds the `--no-ff` merge **in the change's
worktree**, re-runs the whole suite and the adapters there, and on green
fast-forwards the primary branch onto that merge commit. Then it removes the
worktree and deletes the branch. The confirmation is the suite on the exact
commit that lands, not the merge succeeding. A red land never touched the
primary tree, and the worktree is back on its branch, even when the land
was killed.

## 0: landed and green

The merge is in, the suite passed on the merge commit, the worktree and branch
are gone. Confirm to the user what landed, the Decisions and Notes written, and
what was deleted.

When the suite left files in the worktree, git keeps it. The receipt then
names the files and prints the `worktree.sh remove` command. The change has
landed, so nothing there needs a commit. Delete the files and run that
command.

## 6: the merge failed a check

The primary branch did not move, and the worktree is back on its branch as
evidence. This is stop-point 1 surfacing at land: the change passed in
isolation but not against what else has landed since. **Stop and escalate.**
Do not run land again to see whether it passes this time. A flake is a
finding, and the person decides.

Read the message first: it names what failed (the suite, `typecheck`, `lint`,
`setup-tree`, or a git hook that refused the merge commit). A `setup-tree` red
means the install step failed for the merge, not that the change regressed
anything. A refused hook can fail on the trunk alone, for example a
generated file that is out of date. Then every land fails the same way until a
person fixes the trunk. One more case wears this
exit. Take a project with **no** `setup-tree.sh`, and a primary branch that
changed a lockfile since the cut. There, the suite red can be the worktree's
stale install rather than the change. The tell is a lockfile in the trunk's
diff since the cut plus a missing-module error in the land log. Shipping a
`scripts/setup-tree.sh` is the durable fix.

## 9: merge conflict

Aborted, tree restored. The message names the conflicting paths. Under `--all`
this means the independence check missed an overlap: fold this change in
serially and flag it for a Decision-level look. Do not force the merge.

## 5: lock timeout, or the primary branch kept moving

A land or a full-suite run held the land lock past the timeout. It can be
this session's own run in the background. Nothing happened to the trunk. Wait for that run to finish, then
re-run land. Never work around the lock.

The same exit has a second cause, and the message names it. The primary
branch moved during each of land's attempts: another session committed onto
it, or in shared mode (a committed `.hone-shared`) another developer landed on
the remote. land merges again on the new tip and verifies again each time, and
publishes only a merge it tested. Wait a moment, then re-run land. Never push
or merge the primary branch by hand.

## 2: usage or repo-state error

The branch does not exist, the primary tree is on a detached HEAD, no
commit on the branch carries a `Cut:` line, or the invocation was
malformed. More causes each name themselves: you ran land from inside the
worktree, or the worktree holds uncommitted changes. It holds untracked
files: commit each one the change needs, and delete the others, because the
suite must see exactly what lands. land could not cut a missing worktree
again, or its `setup-tree` failed. git refused the merge before it started.
Files in the primary tree stopped the fast-forward: they may be another
session's drafts, so move them only if they are yours. The primary tree left
its branch during the land, or `HONE_LAND_RETRIES` is not a whole number.
land never overwrites a file in the primary tree. Nothing was merged. Read
the stderr line. Fix the state rather than retrying blindly: from the
primary tree, or in the worktree when the line asks for an amended commit.

In shared mode, exit 2 also means the host refused the push, or land could
not take its fast-forward back after the push failed. In that second case
the merge is still on the local primary branch, unpushed, and hone pushes
nothing until it is gone. **Stop and hand the human the recovery command**
that the message prints. Never run it yourself: it moves the primary
tree's HEAD.

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
names where you can reach it, then **stop and hand over**. Quote what you ran
and what it printed, verbatim, with the `worktree.sh attest` command the
refusal printed. The sign-off is the human's act. You never run `attest`, and
the `bash-guard` denies it to you. The human reads the output, runs the check
again if they want, and records it. Where the declared check is outside your
reach, stop with what you tried. A report naming a check nobody ran is worse
than no gate, because the human signs on the strength of it.

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
yourself, read its output, and hand it to the human with the attest command.
That run is a real check of the branch's own adapter, so the output you hand
over is honest evidence. The signature stays the human's.

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

The human writes the sign-off with `worktree.sh attest` and nothing else. A
file write or a shell redirect into `.hone-proof/` skips the signer stamp, the
commit binding, and the placeholder check, and both guards deny it. Never
paste a commit id into a file to satisfy the check: the check is the run, not
the file.

## 8: the authority gate

`land` classified the diff as an
*irreversible* change (destructive SQL, a `db/` deletion, a
`.hone-irreversible-paths` match) and found no `.hone-grant/<change>`.

The merge did not happen and the worktree is kept. The refusal quotes
each destructive statement with its file, then a diffstat and the command to
read the whole diff. Read
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
