Step 6 (land) of the change `checkout/express-pay`.

The suite is green, review is clean, and you committed in the worktree. The Plan
declared `Proof: real-environment` (the claim is that a user can complete checkout in
a browser), and you carried that `Proof: real-environment` line in the commit body.

You ran:

    bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" land checkout/express-pay

It exited **7**. There is no `scripts/proof.sh` in the repo, and no
`.hone-proof/checkout/express-pay` file. The merge did not happen and the worktree
was kept.

What is your next action?
