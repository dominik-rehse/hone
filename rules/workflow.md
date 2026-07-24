---
description: "hone: a human writes a short Plan, then an automated worktree-native loop builds, verifies, consolidates, reviews, and lands each change. Only rot-proof durable truth survives, and every cycle deletes something."
---

# hone workflow

Every change runs `plan → run`. A human authors `.plans/<change>.md` (the one
hand-written artifact; use `/hone:plan`, which ends with `plan-critic`
admission while the human is present). Then `/hone:run` executes it unattended
in a git worktree: build (test-first) → verify → consolidate →
`/code-review` → land (merge to the primary tree, re-run the suite, remove the
worktree). It proceeds without checking in and stops only when blocked with no
resolution, genuinely ambiguous, or done. On a stop it leaves the worktree as
evidence and escalates, and never disables a gate.

Durable truth lives only where it can't rot: *types* (make illegal states
unrepresentable), *code* and behaviour-named *tests* in `src/<area>/`,
present-tense *Decisions* (`docs/decisions/<topic>.md`), small per-area *Notes*
(`docs/notes/<area>.md`), and git history. Never write a durable line an agent
could recover from the code, and if something can be a type, make it a type
instead of prose. Everything else (the Plan) is committed at `plan` but removed
at consolidate: git history keeps it, the working tree does not.

A third command, `/hone:garden`, runs the same loop on a schedule to cut
durable-layer drift between changes. It only deletes, and the suite proves each
cut safe. It is maintenance, not a Plan.

Invariants the hooks enforce: the primary tree is a merge target, never a
workspace (`guard`); no production code without a failing test (`guard`); the
suite, type-check, and lint stay green (`gate`); Plans and Notes stay small and
owned (`nag`). `docs/` is written only at consolidate; code and tests only at
build. The detail lives in the `plan`, `run`, and `garden` skills, loaded when
invoked.
