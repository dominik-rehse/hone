---
name: plan
description: "Author the ephemeral Plan for one change: .plans/<change>.md, the only hand-written artifact. Guides sizing a change to the smallest unit worth its own review gate, states what, why, and how you'll know it works, then submits it to the plan-critic for admission while the human is still present to revise. Does not write code, tests, or docs. Invoke with /hone:plan <change-name-or-sketch>."
argument-hint: "[change-name-or-sketch]"
disable-model-invocation: true
---

# /hone:plan — author a change Plan

Input: $ARGUMENTS

The Plan is the one hand-written artifact and the single manual step in hone.
Everything after it (build, verify, consolidate, review, land) runs unattended
from `/hone:run`. So the Plan is a *brief*, not a spec: it says what to build, why,
and how you'll know it works, and then it is deleted at consolidate. It never
accretes acceptance-criteria bookkeeping; the tests are the durable record of
behaviour.

This command helps a human write that brief. It writes **only** `.plans/<change>.md`
(and, when the change rests on an empirical bet, an entry in
`docs/open-questions.md`). It does not write code, tests, or other docs.

## Task

### 1. Name the change

Derive a short, domain-named slug from `$ARGUMENTS` (`auth/refresh-token`,
`export/csv-escaping`), mirroring `src/`. Never a positional name (`change-3`).
The Plan lands at `.plans/<slug>.md`; if that file already exists, ask whether to
resume or overwrite it.

### 2. Size it to one review gate

A change is the **smallest unit worth its own review gate**: split only where a
reviewer could reject one part while approving its neighbour. Too large and the
review can't hold it; too small and you multiply merge overhead on shared files.

- If the sketch is really several independent changes, say so and propose the
  split: one Plan each, each landable alone. Independent means disjoint `src/`
  files (they can run in parallel worktrees; `run` re-checks independence
  before fanning out, and the merge verifies it).
- If it's one indivisible change spanning several files, that's one Plan.

Decide this now; the `plan-critic` (step 5) will challenge a Plan whose scope is
wrong.

### 3. Surface empirical bets as open questions

If the change rests on an assumption only running code can settle (a driver's
dialect, an SDK's headless behaviour, a library on this runtime), record it in
`docs/open-questions.md` as a question gated to this change, not in the Plan.
Distinct from a *decision already made* (that's a Decision, written at
consolidate). Don't invent questions to fill the file.

### 4. Write `.plans/<slug>.md`

Keep it to what an unattended loop needs and no more:

```markdown
# Plan: <slug>

## What
<2–4 sentences: the change, at the level of observable behaviour.>

## Why
<The reason now: the user need, the bug, the constraint. One short paragraph.>

## How I'll know it works
<The observable proof: the behaviour a test will pin, the end-to-end check, the
error that stops reproducing. Concrete and checkable, not "it works".>

## Notes for the loop (optional)
- <Critical path? Name it: it earns a mutation check and maybe a property test.>
- <A Decision this change makes or changes (topic + the why), for consolidate.>
- <Files/areas expected to change; whether this is independent of in-flight work.>
- <Open question OQ-N this change resolves, if any.>
```

Omit any section that would only restate another. No placeholders, no `TBD`: the
`plan-critic` rejects them at admission, next.

### 5. Admit — `plan-critic`

Submit the finished Plan to the `plan-critic` agent (Task tool,
`subagent_type: plan-critic`). Give it a **constructed brief**: the Plan text,
the list of open changes (other `.plans/**/*.md` — slugs nest — and existing
`hone/*` worktrees), and the relevant existing Decisions/Notes, never your own
transcript. It returns structured findings and an `ADMIT`/`REJECT` verdict.

**If it rejects** (placeholder, contradiction, ambiguity, wrong scope, collision
with an open change, or contract churn): this is the moment to fix it — the
human is still here. Present the findings, revise the Plan with the human (they
own it), and resubmit the revised Plan. Never hand off a rejected Plan:
`/hone:run` executes unattended and trusts that admission happened here.

### 6. Confirm — the hand-off

Close with an explicit hand-off. The Plan file is easy to lose track of: it
lives in a hidden dot-directory, it is gitignored (so `git status` won't list
it), and the slug you derived may differ from the name the user typed. State
all of that plainly:

> Plan written to `.plans/<slug>.md` and admitted by the `plan-critic` — on disk
> in your checkout, on your current branch. It won't show in `git status`
> (`.plans/` is gitignored by design; the Plan is ephemeral and consolidate
> deletes it).
> [I named it `<slug>` rather than `<what-you-typed>` to mirror `src/`.]
> [Open question added to `docs/open-questions.md`.]
> Run `/hone:run <slug>` to build, verify, consolidate, review, and land it, or
> `/hone:run` to pick it up with any other ready Plans.

Do not start building. `/hone:run` owns everything after the Plan.
