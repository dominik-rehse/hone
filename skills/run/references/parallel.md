# `--all`: running many Plans at once

Background for `/hone:run --all`. Read this when the invocation is `--all`; a
single named change never needs it.

Parallelism is `run` over several Plans, not a special mode, and it is never
assumed. **Check independence first, before spawning any worktree.** Each
`plan-critic` ran at plan time, before later Plans existed, so this is the first
moment the whole set is visible and the cross-check is yours.

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
  *What*, a quick look at `src/`);
- any shared type or persistent contract (a DB schema, a public API, a wire or
  file format);
- any Decision or Note more than one would touch;
- any **reference** two Plans both name. A shared fixture or schema file is a
  hard signal: they are not independent even if their `src/` files are disjoint.

Then partition:

- **Disjoint Plans** run in parallel: steps 1–5 each in its own worktree,
  concurrently.
- **Overlapping Plans** run sequentially: order them (foundation first: the Plan
  the others build on), and run each fully through step 6 before starting the
  next, so the later change builds on the landed result instead of fighting it at
  the merge. Sequencing is your call; it needs no escalation.

State the partition and its reason before starting ("`a` and `b` are disjoint:
parallel; `c` touches the same schema as `a`: after `a` lands").

## Claims

A change whose `add` exits **4** is already claimed by another `run` sharing this
repo: **skip it** and note the skip in the partition report; never adopt its
worktree. This is what keeps two concurrent `/hone:run` invocations from both
building the same Plan: the worktree is a single atomic claim.

## Landing

Land them one at a time through step 6:

- Lands are serialized by the land lock even across sessions, so `worktree.sh
  land` never interleaves two merges; within this run, still drive them one at a
  time so each builds on the last landed result.
- The upfront check is a judgment; the **merge verifies it**. A merge collision
  on a shared type, Decision, or Note (`land` exit 9) means the check missed an
  overlap: fold it into one serial change and flag it for a Decision-level look.
  Do not force the merge.
- After all merges, run one **global consolidate pass** (a `consolidate-critic`
  over the combined result) to catch cross-change duplication no single worktree
  could see.
