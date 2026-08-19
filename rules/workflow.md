---
description: "hone: a human writes a short Plan, then an automated loop builds, verifies, consolidates, reviews, and lands each change in a git worktree. Docs are kept minimal and checked, and every change should delete something."
---

# hone workflow

Every change runs `plan → run`. `/hone:plan` writes `.plans/<change>.md`, the
one artifact written outside the loop. A human usually invokes it, and another
agent may invoke it too. The command ends with the `plan-critic` check while
its caller can still revise the Plan. `/hone:run` then
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

Exploration has its own two homes, because a probe is not a change. Throwaway
code lives in `spikes/`, which is gitignored and which no hook guards. Delete
it once it has answered its question. Where the investigation is worth keeping
after that, it becomes one frozen note at
`docs/spikes/<YYYY-MM-DD>-<slug>.md`. Write that note once, in the past tense,
and never maintain it against the code. It always points forward to the
Decision, Note, or Plan that now carries the finding. Companion evidence shares
the note's stem
(`<YYYY-MM-DD>-<slug>.html`). The date is what exempts a spike note from the
staleness rules above. Do not open `docs/spikes/` before a spike's evidence
actually outlives its conclusion.

Memory the harness saves outside the repo is not project documentation: it is
per-user, unreviewed, uncommitted, and invisible to the hooks, the critics,
and `garden`, so a decision or invariant stored there governs nothing. Read
it as background; when something in it belongs to the codebase, land it in
`docs/` through consolidate.

A third command, `/hone:garden`, runs the same loop between changes and only
deletes (stale docs, dead code, redundant tests), with the suite proving
each removal safe. A human invokes it; it is maintenance, not a Plan.

A shell command reaches the same durable paths the file tools do. Dependency
work, a formatter run, and a schema migration all write their files from
inside their own tool, where `guard` sees no path at all. Run them in a
worktree like any other change, never in the primary tree. The `dirty-guard`
hook reports such a write after the fact, and a report is not a prevention. A
dependency or toolchain refresh has a named shape, and the `plan` and `run`
skills point to it.

The hooks enforce: the primary tree is a merge target, never a workspace
(`guard`); no production code without a failing test (`guard`); tests,
type-check, and lint stay green (`gate`); Plans and Notes stay small and
owned (`nag`). `docs/` is written only at consolidate; code and tests only at
build. The detail lives in the `plan`, `run`, and `garden` skills, loaded
when invoked.
