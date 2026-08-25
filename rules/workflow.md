---
description: "hone: a human writes a short Plan, then an automated loop builds, verifies, consolidates, reviews, and lands each change in a git worktree. Docs are kept minimal and checked, and every change should delete something."
---

# hone workflow

Every change runs `plan → run`. `/hone:plan` writes `.plans/<change>.md`, the
one artifact written outside the loop. A human usually invokes it, and another
agent may invoke it too. The command ends with the `plan-critic` check while
its caller can still revise the Plan. `/hone:run` then
executes the Plan unattended in a git worktree. The loop is build (test-first)
→ verify → consolidate → `/code-review` → land (merge into the primary tree,
re-run the suite, remove the worktree). It proceeds without checking in, and
stops only when a check cannot be made green, the change is genuinely
ambiguous, or it is done. On a stop it keeps the worktree as evidence and
reports the blocker. It never disables a check to proceed.

Permanent documentation lives only in forms that get checked or stay small:
types (make invalid states impossible to express), code and behavior-named
tests in `src/<area>/`. The rest is present-tense Decisions
(`docs/decisions/<topic>.md`), small per-area Notes (`docs/notes/<area>.md`),
and git history. Never write down what an agent could work out from the code.
If something can be a type, make it a type instead of prose. The Plan is
committed at plan time but deleted at consolidate: git history keeps it, the
working tree does not.

Exploration has its own home, because a probe is not a change. Everything one
spike leaves behind lives under `docs/spikes/`, whatever its type: the note,
the probe code that produced it, a mockup, a captured payload. One spike is one
dated stem, `<YYYY-MM-DD>-<slug>`, a single file where one file is enough and a
directory where it is not. No hook guards what sits inside, so a probe needs no
test and no worktree.

The note at `<YYYY-MM-DD>-<slug>.md` is the way in. Write it once, in the past
tense, and never maintain it against the code. It always points forward to the
Decision, Note, or Plan that now carries the finding. The date is what exempts
a spike from the staleness rules above. So nothing here is ever updated, only
added or removed whole. Commit a spike only when its method or its dead ends
are worth keeping. Most probes answer their question and leave nothing behind.

Memory the harness saves outside the repo is not project documentation. It is
per-user, unreviewed, uncommitted, and invisible to the hooks, the critics,
and `garden`, so a decision or invariant stored there governs nothing. Read
it as background. When something in it belongs to the codebase, land it in
`docs/` through consolidate.

A third command, `/hone:garden`, runs the same loop between changes and only
deletes (stale docs, dead code, redundant tests). The suite proves each
removal safe. A human or another agent invokes it. It is maintenance,
not a Plan.

A shell command reaches the same durable paths the file tools do. Dependency
work, a formatter run, and a schema migration all write their files from
inside their own tool, where `guard` sees no path at all. Run them in a
worktree like any other change, never in the primary tree. The `dirty-guard`
hook reports such a write after the fact, and a report is not a prevention. A
dependency or toolchain refresh has a named shape, and the `plan` and `run`
skills point to it.

The hooks enforce these rules. The primary tree is a merge target, never a
workspace (`guard`). No production code without a failing test (`guard`).
Tests, type-check, and lint stay green (`gate`). Plans and Notes stay small
and owned (`nag`). `docs/` is written only at consolidate, apart from spikes
and plan-time open questions. Code and tests are written only at build. The
detail lives in the `plan`, `run`, and `garden` skills, loaded when invoked.

Work with a denied action, never around it. A denied write in the primary
tree is a routing signal. The work belongs in a worktree, and a docs edit
belongs in that change's consolidate step. Creating the `.hone-off` marker is
the human's act alone, so ask them to create it. Removing an existing marker
is a legitimate agent action. Write a grant or a proof sign-off only through
`worktree.sh grant` / `worktree.sh attest`, and record only a check that
actually ran, quoting its output. Never attest a failed or partial run. The
`bash-guard` reads command text, so it can escalate an innocent command that
merely mentions a protected path. Rephrase such a command instead of routing
around the hook.
