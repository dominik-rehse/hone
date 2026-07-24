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

Decide this now; the `plan-critic` (the admission critic run at step 5) will
challenge a Plan whose scope is wrong.

### 3. Surface empirical bets as open questions

If the change rests on an assumption only running code can settle (a driver's
dialect, an SDK's headless behaviour, a library on this runtime), record it in
`docs/open-questions.md` as a question gated to this change, not in the Plan.
Distinct from a *decision already made* (that's a Decision, written at
consolidate). Don't invent questions to fill the file.

One question is never an open question — it goes to the human, now: if the
change touches a persistent schema (a migration, a stored format), ask **"is
the existing data worth preserving?"** before any migration design, and record
the answer in the Plan's *Notes for the loop*. Everything downstream hinges on
it — disposable data collapses backfill design into drop-and-recreate — and the
`plan-critic` rejects a schema-touching Plan that leaves it unstated.

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
<If the claim is user- or ops-level and no in-repo test can settle it (a browser
journey, a canary, deployed health), say so and add a `Proof: real-environment`
line; otherwise the proof is assertion-level and the gate's suite covers it.>

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

### 6. Commit the admitted Plan

The Plan is a tracked artifact. Commit it now — only once admitted — to the
current branch:

```bash
git add .plans/<slug>.md
git commit -m "chore(plan): <slug>"
```

Two reasons it must be committed here, not left loose: `/hone:run` builds its
worktree off the trunk's HEAD, so the Plan has to be on HEAD for the run to see
it; and committing it is what lets consolidate remove it cleanly — a `git rm`
inside the worktree that the landing merge carries back to the primary tree —
instead of an out-of-band delete of an untracked file (which the unattended run
cannot perform). Commit nothing but the Plan; the loop owns every other artifact.

### 7. Confirm — the hand-off

Close with an explicit hand-off. The slug you derived may differ from the name
the user typed, so state it plainly:

> Plan written to `.plans/<slug>.md`, admitted by the `plan-critic`, and committed
> on `<branch>`. It is tracked — it shows in `git log`, not as an untracked file;
> the change's landing merge removes it from the tree, and git history keeps it.
> [I named it `<slug>` rather than `<what-you-typed>` to mirror `src/`.]
> [Open question added to `docs/open-questions.md`.]
> Run `/hone:run <slug>` to build, verify, consolidate, review, and land it, or
> `/hone:run` to pick it up with any other ready Plans.

Do not start building. `/hone:run` owns everything after the Plan.
