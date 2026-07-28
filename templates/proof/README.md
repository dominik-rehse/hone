# Real-environment proof adapter contract

`scripts/proof.sh` is the adapter for the *proof gate*. It is a different thing
from the test tiers in `templates/run-tests/`: those assert against the working
tree, this one proves the change against a **real environment** (a browser
journey, a canary, deployed health, a real API). It runs only when a change
declared `Proof: real-environment` in its Plan, and only at land, before the
merge. Copy a template here to `scripts/proof.sh` and adapt it.

## Contract

- `land` executes the **primary tree's copy** of the adapter — the reviewed,
  already-landed one — so a change cannot ship an always-green `proof.sh` of
  its own. A change that introduces or edits `proof.sh` is trusted only after
  that adapter change has landed; until then, the human sign-off is the way
  through the gate.
- Invoked as `proof.sh <change>`, with the working directory set to the
  **change's worktree** when it exists — that tree holds the code under test.
  The primary tree is still pre-merge at this point, so proving against it would
  green-light the change on the old code's behaviour.
- Environment: `HONE_CHANGE` (the change name), `HONE_BRANCH` (`hone/<change>`),
  `HONE_WORKTREE` (absolute path, empty if the worktree is gone),
  `HONE_MAIN_ROOT` (the primary tree).
- Exit `0` = proven in the real environment; non-zero = not proven, and `land`
  refuses with exit 7 and keeps the worktree.
- It must leave nothing running and nothing mutated: start what it needs, prove,
  tear down. `land` holds the land lock while it runs.

The adapter is optional. Without it, a real-environment change needs a human
sign-off at `.hone-proof/<change>` naming the commit it proved.

## The instance is the hard part

Proving a change pre-merge means getting *that branch* running somewhere real.
How far that is from a checkout differs by project, and it decides whether this
adapter is worth writing at all:

*The checkout is the artifact.* A CLI over local files runs straight from the
worktree. Start from `cli.sh`; nothing needs provisioning.

*The checkout plus credentials.* A client of a real external API needs an
account to talk to, ideally one set aside for this. Still `cli.sh`, with an
isolated config/state root so a proof run cannot touch real state.

*The checkout plus infrastructure.* A long-running service needs a second
instance beside production: its own port, its own database copy, the same
secrets. Start from `service.sh`. If a project can only run its real
environment in production, that instance has to be built before this adapter
can exist — until then, the honest way through the gate is the human sign-off.

Name every instance after `$HONE_CHANGE` rather than hardcoding one. Two changes
can be in flight at once, and an instance they share is one that proves neither.
