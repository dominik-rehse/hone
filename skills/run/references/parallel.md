# `--all`: running many Plans at once

Background for `/hone:run --all`. Read this when the invocation is `--all`. A
single named change never needs it.

Parallelism is `run` over several Plans, not a special mode, and it is never
assumed. **Check independence first, before spawning any worktree.** Each
`plan-critic` ran at plan time, before later Plans existed. This is the first
moment the whole set is visible, and the cross-check is yours.

## Where the runs happen

Ask the environment, before the partition:

```bash
test "${HERDR_ENV:-}" = 1
```

- It **fails**: run the Plans in this session, as the rest of this file
  describes. That is the ordinary case.
- It **passes**: this session runs inside herdr, so spread the Plans over herdr
  tabs. This session becomes MAIN and orchestrates. Each Plan gets a fresh
  Claude Code session in its own SUB tab. Read `references/herdr.md` and follow
  it. Everything below still holds. The tabs only change where each run
  executes.

## Partition

Read every ready Plan and compare them pairwise:

- the files and areas each expects to change (its *Notes for the loop*, its
  *What*, a quick look at `src/`).
- any shared type or persistent contract (a DB schema, a public API, a wire or
  file format).
- any Decision or Note more than one would touch. A Plan's file list names
  `src/` files and under-declares this. So read each Plan for the doc topics
  its consolidate step will edit. That means the Decision it makes, the Note
  it amends, the open question it closes. Consolidate is where parallel lands
  actually collide.
- any **reference** two Plans both name. A shared fixture or schema file is a
  hard signal: they are not independent even if their `src/` files are disjoint.

Then partition:

- **Disjoint Plans** run in parallel: steps 1–5 each in its own worktree,
  concurrently.
- **Overlapping Plans** run sequentially. Order them (foundation first: the Plan
  the others build on). Run each fully through step 6 before starting the next.
  The later change then builds on the landed result instead of fighting it at
  the merge. Sequencing is your call. It needs no escalation.

State the partition and its reason before starting ("`a` and `b` are disjoint:
parallel. `c` touches the same schema as `a`: after `a` lands").

## Shared ledgers

A single shared file every change may touch (`docs/open-questions.md`, a
roadmap the project keeps) collides in its own way. Edits land as adjacent
hunks in one file, so the second land conflicts. An id ledger collides
silently. Two worktrees cut from the same base take the same next free
open-question id. Each tree's suite stays green, because each tree's own
file still holds that id free. The merge is what puts both entries in one
file, so the collision first appears at land. Two rules:

- Parallel Plans do not each edit a shared ledger. Give the shared edits
  (roadmap pruning, cross-change bookkeeping) to one docs-only follow-up Plan
  that runs last, alone. That Plan confirms each sibling landed by reading
  the landed code, never git history. When a check fails, it stops and
  reports rather than deletes. It is also the home for a finding a sibling
  run surfaced but could not file.
- A change may still close or add an open question of its own, when no
  sibling in the same fan-out touches that file. On an id collision at land,
  renumber to the next free id on the current trunk, fold the trunk in, and
  land again.

## Claims

A change whose `add` exits **4** is already claimed by another `run` sharing this
repo. **Skip it** and note the skip in the partition report. Never adopt its
worktree. This is what keeps two concurrent `/hone:run` invocations from both
building the same Plan: the worktree is a single atomic claim.

## Landing

Land them one at a time through step 6:

- The land lock serializes lands even across sessions, so `worktree.sh land`
  never interleaves two merges. Within this run, still drive them one at a
  time so each builds on the last landed result.
- The upfront check is a judgment. The **merge verifies it**. A merge collision
  on a shared type, Decision, or Note (`land` exit 9) means the check missed an
  overlap. Fold it into one serial change and flag it for a Decision-level look.
  Do not force the merge.
- After all merges, run one **global consolidate pass** (a `consolidate-critic`
  over the combined result) to catch cross-change duplication no single worktree
  could see.
