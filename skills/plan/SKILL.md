---
name: plan
description: "Author the temporary Plan for one change: .plans/<change>.md, the only hand-written artifact, plus any references under .plans/<change>/ that carry what prose would lose. Guides sizing a change to the smallest unit worth its own review gate, states what, why, and how you'll know it works, then submits it to the plan-critic for approval while the human is still present to revise. Does not write code, tests, or docs. Invoke with /hone:plan <change-name-or-sketch>."
argument-hint: "[change-name-or-sketch]"
disable-model-invocation: true
---

# /hone:plan (author a change Plan)

Input: $ARGUMENTS

The Plan is the one hand-written artifact and the single manual step in hone.
Everything after it (build, verify, consolidate, review, land) runs unattended
from `/hone:run`. So the Plan is a short brief, not a spec: it says what to
build, why, and how you'll know it works, and it is deleted at consolidate. It
never accumulates acceptance-criteria bookkeeping; the tests are the permanent
record of behaviour.

This command helps a human write that brief. It writes **only** `.plans/<change>.md`
(and, when the change rests on an untested assumption, an entry in
`docs/open-questions.md`). It does not write code, tests, or other docs.

## Task

### 1. Name the change

Derive a short, domain-named slug from `$ARGUMENTS` (`auth/refresh-token`,
`export/csv-escaping`), mirroring `src/`. Never a positional name (`change-3`).
The Plan lands at `.plans/<slug>.md`; if that file already exists, ask whether to
resume or overwrite it.

One naming rule guards the layout's one ambiguity. A Plan's references live in
`.plans/<slug>/`, so a markdown file whose parent directory has a sibling
`<dir>.md` is read as a *reference*, not a Plan, by the nag and by
`worktree.sh status`. A slug therefore may not double as a Plan directory:

- If the slug is nested (`a/b`) and `.plans/a.md` exists, refuse the name: the
  new Plan at `.plans/a/b.md` would look like a reference of Plan `a` and drop
  out of every pending-Plan scan. Propose a sibling name instead (`a-b`, or a
  different area).
- If the slug is `a` and `.plans/a/` already holds other Plans (an `a/x.md`
  with no `.plans/a.md` beside it), refuse it for the mirror reason: creating
  `.plans/a.md` would turn those Plans into apparent references.

State the conflict and agree on an alternative with the human; never silently
rename.

### 2. Size it to one review gate

A change is the **smallest unit worth its own review gate**: split only where a
reviewer could reject one part while approving its neighbour. Too large and the
review can't hold it; too small and you multiply merge overhead on shared files.

- If the sketch is really several independent changes, say so and propose the
  split: one Plan each, each landable alone. Independent means disjoint `src/`
  files (they can run in parallel worktrees; `run` re-checks independence
  before fanning out, and the merge verifies it).
- If it's one indivisible change spanning several files, that's one Plan.

Decide this now; the `plan-critic` (the Plan checker run at step 5) will
challenge a Plan whose scope is wrong.

### 3. Surface untested assumptions as open questions

If the change rests on an assumption only running code can settle (a driver's
dialect, an SDK's headless behaviour, a library on this runtime), record it in
`docs/open-questions.md` as a question gated to this change, not in the Plan.
Distinct from a *decision already made* (that's a Decision, written at
consolidate). Don't invent questions to fill the file.

One question is never an open question; it goes to the human, now. If the
change touches a persistent schema (a migration, a stored format), ask **"is
the existing data worth preserving?"** before any migration design, and record
the answer in the Plan's *Notes for the loop*. Everything downstream hinges on
it (disposable data collapses backfill design into drop-and-recreate), and the
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
<If the claim is user- or ops-level and no in-repo test can settle it, say so.
Add a `Proof: real-environment — <the check>` line naming the concrete check:
the browser journey to walk, the canary to watch, the probe to run. The
description is mandatory. Otherwise the proof is assertion-level and the gate's
suite covers it.>

## Notes for the loop (optional)
- <Critical path? Name it: it earns a mutation check and maybe a property test.>
- <A Decision this change makes or changes (topic + the why), for consolidate.>
- <Files/areas expected to change; whether this is independent of in-flight work.>
- <Open question OQ-N this change resolves, if any.>

## References (optional)
- `<path>`: <what it carries, in one line.>
```

Omit any section that would only restate another. No placeholders, no `TBD`: the
`plan-critic` rejects them at the check, next.

### 4a. Attach what prose describes badly

Some things a change depends on survive prose badly: a wire or file format, a
response shape, a table or screen layout, an exact error string, a set of
escaping or boundary cases. Describing one costs paragraphs and still loses
detail, and because the Plan is deleted at consolidate, nothing remains to
check the loop's reading against. Hand over the file instead: the loop reads
it directly, and it is often the fixture the first red test consumes.

A reference is a **file that exists**, never prose moved into a second file:

- *Already in the repo* (a type, a golden file, an existing test, a schema):
  name its path and stop. Do not copy it into the Plan.
- *Written for this change* (a table of input/expected rows, a sample payload, an
  HTML mockup of a screen): put it under `.plans/<slug>/`. That directory belongs
  to the Plan, and it is also the only place you can write one here: `guard`
  denies writes to `docs/`, `src/`, and `tests/` in the primary tree, which is
  where `/hone:plan` runs.

Two limits. If you need a paragraph to explain what a reference *means*, it is
prose in a file's clothing: put the point in *What* and drop the file. And a
reference is not a spec: it pins data the loop would otherwise have to guess,
never the acceptance criteria; those stay the tests' job.

### 5. Check: `plan-critic`

Submit the finished Plan to the `plan-critic` agent (Task tool,
`subagent_type: plan-critic`). Give it a **constructed brief**: the Plan text,
the list of open changes (other `.plans/**/*.md`, since slugs nest, and existing
`hone/*` worktrees), and the relevant existing Decisions/Notes, never your own
transcript. It returns structured findings and an `APPROVE`/`REJECT` verdict.

**If it rejects** (placeholder, contradiction, ambiguity, wrong scope, collision
with an open change, or contract churn): this is the moment to fix it, while the
human is still here. Present the findings, revise the Plan with the human (they
own it), and resubmit the revised Plan. Never hand off a rejected Plan:
`/hone:run` executes unattended and trusts that this check happened here.

### 6. Commit the approved Plan

The Plan is a tracked artifact. Commit it now (only once the critic returns
`APPROVE`) to the current branch:

```bash
git add .plans/<slug>.md .plans/<slug>/   # the second path only if you wrote references
git commit -m "chore(plan): <slug>"
```

Two reasons it must be committed here, not left loose: `/hone:run` builds its
worktree off the trunk's HEAD, so the Plan has to be on HEAD for the run to see
it; and committing it is what lets consolidate remove it cleanly (a `git rm`
inside the worktree that the landing merge carries back to the primary tree)
instead of an out-of-band delete of an untracked file (which the unattended run
cannot perform). Both reasons apply to a reference exactly as they do to the
Plan: an uncommitted reference is invisible inside the worktree, so the build
fails on a missing file it was told to read. Commit nothing but the Plan and its
references; the loop owns every other artifact.

### 7. Confirm: the hand-off

Close with an explicit hand-off. The slug you derived may differ from the name
the user typed, so state it plainly:

> Plan written to `.plans/<slug>.md`, approved by the `plan-critic`, and committed
> on `<branch>`. It is tracked: it shows in `git log`, not as an untracked file;
> the change's landing merge removes it from the tree, and git history keeps it.
> [I named it `<slug>` rather than `<what-you-typed>` to mirror `src/`.]
> [Open question added to `docs/open-questions.md`.]
> Run `/hone:run <slug>` to build, verify, consolidate, review, and land it, or
> `/hone:run` to pick it up with any other ready Plans.

Do not start building. `/hone:run` owns everything after the Plan.
