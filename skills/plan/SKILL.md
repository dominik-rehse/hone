---
name: plan
description: "Author the temporary Plan for one change: .plans/<change>.md, the one artifact written outside the loop, plus any references under .plans/<change>/ that carry what prose would lose. Guides sizing a change to the smallest unit worth its own review gate, states what, why, and how you'll know it works, then submits it to the plan-critic for approval while the caller is still present to revise. Does not write code, tests, or docs. Invoke with /hone:plan <change-name-or-sketch>."
argument-hint: "[change-name-or-sketch]"
---

# /hone:plan (author a change Plan)

Input: $ARGUMENTS

The Plan is the one artifact written outside the loop. It is the single step
that still needs a caller, and that caller is a human or another agent.
Everything after it (build, verify, consolidate, review, land) runs unattended
from `/hone:run`. So the Plan is a short brief, not a spec. It says what to
build, why, and how you'll know it works, and it is deleted at consolidate. It
never accumulates acceptance-criteria bookkeeping. The tests are the permanent
record of behaviour.

This command helps its caller write that brief. It writes **only** `.plans/<change>.md`
(and, when the change rests on an untested assumption, an entry in
`docs/open-questions.md`). It does not write code, tests, or other docs.

## Task

### 1. Name the change

Derive a short, domain-named slug from `$ARGUMENTS` (`auth/refresh-token`,
`export/csv-escaping`), mirroring `src/`. Never a positional name (`change-3`).
The Plan lands at `.plans/<slug>.md`. If that file already exists, ask whether to
resume or overwrite it.

One naming rule guards the layout's one ambiguity. A Plan's references live in
`.plans/<slug>/`. So the nag and `worktree.sh status` read a markdown file whose
parent directory has a sibling `<dir>.md` as a *reference*, not a Plan. A slug
therefore may not double as a Plan directory:

- If the slug is nested (`a/b`) and `.plans/a.md` exists, refuse the name. The
  new Plan at `.plans/a/b.md` would look like a reference of Plan `a` and drop
  out of every pending-Plan scan. Propose a sibling name instead (`a-b`, or a
  different area).
- If the slug is `a` and `.plans/a/` already holds other Plans (an `a/x.md`
  with no `.plans/a.md` beside it), refuse it for the mirror reason. Creating
  `.plans/a.md` would turn those Plans into apparent references.

State the conflict and agree on an alternative with the caller. Never silently
rename.

### 2. Read what the change will touch

Start from the code, not from the sketch. A Plan that alters behaviour which
already exists has to say what that behaviour is today. Nobody downstream can
recover it: the loop reads the code it is about to replace, and the human at
land time reads only the commit.

Read three things for each area the sketch names: the files under `src/<area>/`,
the tests beside them, and that area's Note and Decisions. The tests state what
the system does now. A Decision may already settle the question the sketch
reopens, which changes the Plan or cancels it.

Then sort what you found into four outcomes, and carry each into the Plan:

- *preserve*: behaviour the change keeps. Tests already pin it. Name it in
  *What* so the loop does not rewrite it in passing.
- *verify*: behaviour the change depends on that no test pins. Say so in *Notes
  for the loop*. The build writes that test before it touches the code.
- *redesign*: behaviour the change replaces. *What* opens with what the code
  does today, then states the replacement.
- *remove*: behaviour the change deletes. Name the files in *Notes for the
  loop*. A deletion the loop has to infer is a deletion it skips.

A change that opens a new area finds nothing to sort. Write one line saying the
area is new, and go on. Never invent a baseline for code that does not exist.

### 3. Size it to one review gate

A change is the **smallest unit worth its own review gate**: split only where a
reviewer could reject one part while approving its neighbour. Too large and the
review can't hold it. Too small and you multiply merge overhead on shared files.

- If the sketch is really several independent changes, say so and propose the
  split: one Plan each, each landable alone. Independent means disjoint `src/`
  files (they can run in parallel worktrees). `run` re-checks independence
  before fanning out, and the merge verifies it.
- If it's one indivisible change spanning several files, that's one Plan.

Decide this now. The `plan-critic` (the Plan checker run at step 6) will
challenge a Plan whose scope is wrong.

### 4. Surface untested assumptions as open questions

The change may rest on an assumption only running code can settle: a driver's
dialect, an SDK's headless behaviour, a library on this runtime. Record it in
`docs/open-questions.md` as a question gated to this change, not in the Plan.
Distinct from a *decision already made* (that's a Decision, written at
consolidate). Don't invent questions to fill the file.

Where the assumption decides the *shape* of the Plan, an open question is too
slow. A Plan written on a guess is a Plan the loop builds wrong. Settle it now
with a **spike**. Probe it under `docs/spikes/`, where no hook guards what you
write, so there is no test to write first and no worktree to spawn. Read the
answer and write the Plan from what you learned. The question never reaches
`docs/open-questions.md`, because running code already answered it.

Then decide whether the spike is worth keeping, and keep or delete it whole:

- *Delete it* when the conclusion is the whole value. This is the usual case.
  The finding lands in the Plan, and nothing stays behind.
- *Keep it* when the method or the dead ends would save a future reader from
  running the same probe. Then everything the spike produced stays under one
  dated stem, `docs/spikes/<YYYY-MM-DD>-<slug>`: the probe code, whatever it
  captured, and a note at `<YYYY-MM-DD>-<slug>.md` copied from
  `${CLAUDE_PLUGIN_ROOT}/templates/spike-note.md`. Use a directory of that name
  where one file is not enough. Commit it with the Plan.

You write all of this here, in the primary tree: `docs/spikes/` is the one path
under `docs/` the guard leaves open, because a probe precedes the Plan. What
you keep is dated and frozen from then on, so nobody updates it later.

One warning about committed probe code. The project's test runner, linter, or
type-checker may pick up a file under `docs/spikes/`, and the gate needs all
three green. Exclude the directory in those adapters the first time a spike
trips one.

One question is never an open question. It goes to the caller, now. If the
change touches a persistent schema (a migration, a stored format), ask **"is
the existing data worth preserving?"** before any migration design. Record
the answer in the Plan's *Notes for the loop*. Everything downstream hinges on
it (disposable data collapses backfill design into drop-and-recreate), and the
`plan-critic` rejects a schema-touching Plan that leaves it unstated.

### 5. Write `.plans/<slug>.md`

Keep it to what an unattended loop needs and no more:

```markdown
# Plan: <slug>

## What
<2–4 sentences: the change, at the level of observable behaviour.>
<Where the change alters behaviour that already exists, open with what that
behaviour is today. One sentence, taken from the code you read at step 2.>

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
- <Behaviour the change removes, and the files that hold it, named exactly.>
- <Behaviour the change relies on that no test pins yet.>
- <Open question OQ-N this change resolves, if any.>

## References (optional)
- `<path>`: <what it carries, in one line.>
```

Omit any section that would only restate another. No placeholders, no `TBD`: the
`plan-critic` rejects them at the check, next.

### 5a. Attach what prose describes badly

Some things a change depends on survive prose badly: a wire or file format, a
response shape, a table or screen layout. Others are an exact error string, a
set of escaping or boundary cases. Describing one costs paragraphs and still
loses detail, and because the Plan is deleted at consolidate, nothing remains to
check the loop's reading against. Hand over the file instead: the loop reads
it directly, and it is often the fixture the first red test consumes.

A reference is a **file that exists**, never prose moved into a second file:

- *Already in the repo* (a type, a golden file, an existing test, a schema):
  name its path and stop. Do not copy it into the Plan.
- *Written for this change* (a table of input/expected rows, a sample payload, an
  HTML mockup of a screen): put it under `.plans/<slug>/`. That directory belongs
  to the Plan, and it is also the only place you can write one here. `guard`
  denies writes to `docs/`, `src/`, and `tests/` in the primary tree, which is
  where `/hone:plan` runs. (`docs/spikes/` is the one exception, and it takes
  a frozen spike note, never a Plan's reference.)

The sketch may be a **dependency or toolchain refresh**: a version bump of a
library, linter, formatter, build tool, or runtime. Then read
`${CLAUDE_PLUGIN_ROOT}/skills/run/references/dependency-refresh.md` before
writing the Plan. It carries the probe to run, the counts and findings the Plan
must pin as expected data, and the test-first exemption a bump gets.

Two limits. If you need a paragraph to explain what a reference *means*, it is
prose in a file's clothing. Put the point in *What* and drop the file. And a
reference is not a spec. It pins data the loop would otherwise have to guess,
never the acceptance criteria. Those stay the tests' job.

### 6. Check: `plan-critic`

Submit the finished Plan to the `plan-critic` agent (Task tool,
`subagent_type: plan-critic`). Give it a **constructed brief**: the Plan text,
the list of open changes, and the relevant existing Decisions/Notes, never your
own transcript. Open changes are other `.plans/**/*.md`, since slugs nest, and
existing `hone/*` worktrees. It returns structured findings and an
`APPROVE`/`REJECT` verdict.

**It may reject** for a placeholder, contradiction, ambiguity, wrong scope,
collision with an open change, or contract churn. Then this is the moment to fix
it, while the caller is still here. Present the findings, revise the Plan with
the caller (they own it), and resubmit the revised Plan. Never hand off a
rejected Plan: `/hone:run` executes unattended and trusts that this check
happened here.

### 7. Commit the approved Plan

The Plan is a tracked artifact. Commit it now (only once the critic returns
`APPROVE`) to the current branch:

```bash
git add .plans/<slug>.md .plans/<slug>/   # the second path only if you wrote references
git commit -m "chore(plan): <slug>"
```

Two reasons it must be committed here, not left loose. First, `/hone:run` builds
its worktree off the trunk's HEAD, so the Plan has to be on HEAD for the run to
see it. Second, committing it is what lets consolidate remove it cleanly. That
removal is a `git rm` inside the worktree that the landing merge carries back to
the primary tree. The alternative is an out-of-band delete of an untracked file,
which the unattended run cannot perform. Both reasons apply to a reference
exactly as they do to the Plan. An uncommitted reference is invisible inside the
worktree, so the build fails on a missing file it was told to read. Commit
nothing but the Plan and its references. The loop owns every other artifact.

### 8. Confirm: the hand-off

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
