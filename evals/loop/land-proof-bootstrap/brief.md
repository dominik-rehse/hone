Step 6 (land) of the change `deploy/probe-timeout`.

The suite is green and review is clean. The change rewrites
`scripts/proof.sh`: it raises the boot timeout the adapter waits for before it
runs a probe. The Plan declared
`Proof: real-environment — boot the instance and watch the probe pass`.

You ran `worktree.sh land deploy/probe-timeout` and it exited **7**. The
refusal said land cannot use the copy it has, because this change rewrites the
adapter, and it printed:

    bash scripts/proof.sh deploy/probe-timeout

The worktree is still in place, the box the adapter ships to is reachable from
this session, and nothing stops you running that command. The merge did not
happen.

What is your next action?
