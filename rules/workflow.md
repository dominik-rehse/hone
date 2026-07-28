---
description: "hone: a human writes a short Plan, then an automated loop builds, verifies, consolidates, reviews, and lands each change in a git worktree. Docs are kept minimal and checked, and every change should delete something."
---

# hone workflow

Every change runs `plan → run`. A human writes `.plans/<change>.md` with
`/hone:plan`, the only hand-written artifact; the command ends with the
`plan-critic` check while the human is still present. `/hone:run` then
executes the Plan unattended in a git worktree: build (test-first) → verify →
consolidate → `/code-review` → land (merge into the primary tree, re-run the
suite, remove the worktree). It proceeds without checking in, and stops only
when a check cannot be made green, the change is genuinely ambiguous, or it
is done. On a stop it keeps the worktree as evidence and reports the blocker;
it never disables a check to proceed.

Permanent documentation lives only in forms that get checked or stay small:
types (make invalid states impossible to express), code and behavior-named
tests in `src/<area>/`, present-tense Decisions
(`docs/decisions/<topic>.md`), small per-area Notes (`docs/notes/<area>.md`),
and git history. Never write down what an agent could work out from the code;
if something can be a type, make it a type instead of prose. The Plan is
committed at plan time but deleted at consolidate: git history keeps it, the
working tree does not.

Memory the harness saves outside the repo is not project documentation: it is
per-user, unreviewed, uncommitted, and invisible to the hooks, the critics,
and `garden`, so a decision or invariant stored there governs nothing. Read
it as background; when something in it belongs to the codebase, land it in
`docs/` through consolidate.

A third command, `/hone:garden`, runs the same loop between changes and only
deletes (stale docs, dead code, redundant tests), with the suite proving
each removal safe. A human invokes it; it is maintenance, not a Plan.

The hooks enforce: the primary tree is a merge target, never a workspace
(`guard`); no production code without a failing test (`guard`); tests,
type-check, and lint stay green (`gate`); Plans and Notes stay small and
owned (`nag`). `docs/` is written only at consolidate; code and tests only at
build. The detail lives in the `plan`, `run`, and `garden` skills, loaded
when invoked.
