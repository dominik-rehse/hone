---
name: garden
description: "Run hone's continuous-maintenance loop: scan the whole repo for staleness that built up between changes (orphan/oversized Notes, broken Governs links, redundant tests, dead code, stale open questions, drift in the project's own CLAUDE.md and skills), then land the safe cuts one at a time through the same worktree loop. Deletion-only: every garden change removes something and the suite proves the cut safe. Escalates judgment calls instead of forcing them. Invoke with /hone:garden, or on a schedule."
argument-hint: "[area-or-scope]"
disable-model-invocation: true
---

# /hone:garden — cut drift between changes

Input: $ARGUMENTS

`plan → run` refines the codebase *at the point of change*: each change cuts its
own leftovers. But staleness also accumulates *between* changes: a Decision whose code
moved, a Note nobody re-derived, a test made redundant by a later change, an open
question running code already settled. Nothing in the change-triggered loop looks
at the repo as a whole. `garden` is that standing look: it runs the same loop on a
schedule, driven by a scan instead of a Plan, and its unit of work is a **cut**.

`garden` writes no new behaviour. Every garden change is **deletion-only**, and
the gate's suite is the proof a cut is safe: a deletion that keeps the suite green
was dead; one that reddens it was load-bearing, so the cut is wrong and abandoned.
That makes the whole loop self-verifying: the same mechanical check that lets
`run` land a feature lets `garden` prove a removal.

Resolve `$ARGUMENTS`:

- empty: scan the whole repo.
- `<area>`: scope the scan to `src/<area>/` and its Notes/Decisions.

Setup check: if `scripts/run-tests.sh` is missing, stop and tell the user to run
`/hone:setup`. Without the adapter no cut can be proven safe.

## 1. Scan — find the drift, repo-wide

The Stop-hook `nag` already names most of it on every turn; `garden` runs the same
questions across the whole tree at once and adds the ones a diff-scoped hook can't
see. Collect, don't act yet:

- **Broken Governs link**: a Decision or Note whose `Governs:` path no longer
  exists (the code moved or went away). The prose is stale.
- **Orphan or oversized Note**: a `docs/notes/<area>.md` with no `src/<area>/`, or
  one past the size cap that has drifted toward a spec.
- **Redundant test**: two tests pinning the same behaviour through the same
  surface; a test the codebase made dead.
- **Dead code**: a `src/` symbol or file with no remaining caller (confirm with a
  repo-wide search, not a guess).
- **Resolved open question**: a `docs/open-questions.md` entry running code has
  already settled.
- **Leftover artifact**: a landed Plan never deleted; a `.plans/<change>/`
  reference directory consolidate never settled; a merged `hone/*` branch land
  forgot to remove.
- **Prompt-layer drift**: the project's own instructions to the agent —
  `CLAUDE.md`, `.claude/rules/`, project skills — describing a gotcha the code no
  longer has, a command that no longer exists, or a rule the model now follows
  without being told. This layer accretes exactly like `docs/` and nothing else
  looks at it. Never cut it mechanically (see step 2).
- **Stranded harness memory**: a `type: project` memory the `nag` has been
  flagging. It is not the repo's to delete, so `garden` never touches the file;
  it reports what belongs in `docs/` so a `run` change can land it there.

State the full list before acting. This scan is the artifact that says what the
run covered: a silent scope is indistinguishable from a scan that found nothing.

## 2. Classify — mechanical cut vs judgment

Split every finding two ways:

- **Mechanical cut**: the removal is obvious and the suite can prove it safe: a
  dead symbol, a redundant test, a resolved question, a leftover branch, a stale
  Note or Decision whose `Governs:` path is gone. These `garden` executes. It only
  *cuts*, never edits: a durable doc that should point at moved code (not be
  deleted) is a `run` change, so escalate it; don't rewrite prose here.
- **Judgment**: the removal turns on *why* a durable line exists: is this
  Decision restating code, or does it carry rationale the code can't show? Does
  this Note's invariant still hold? These go to the `consolidate-critic`, never
  auto-deleted. Durable *rationale* is never cut by machine on a hunch.

**Prompt-layer findings are always judgment, never mechanical** — including the
ones that look obvious. Everything else here rests on the suite proving the cut
safe, and *no suite proves a prompt cut safe*: delete a paragraph of `CLAUDE.md`
and every test still passes, because what changed is how an agent behaves next
time, which nothing in the repo measures. Cutting on green here would be cutting
on no evidence at all.

So a prompt cut needs its own proof, and there is only one honest kind: a suite of
cases with known-good answers (as hone pins its own critics and loop instructions
under `evals/`). If the project has one, run it before and after the cut and land
only what holds. If it does not, `garden` does not cut this layer: report the
finding for a human, and propose the eval as its own Plan. An unverified prompt cut
is a guess about future behaviour, and the whole point of deletion-only is that
guesses are not required.

## 3. Cut — one deletion-only change at a time

Run each mechanical cut (and each critic-accepted judgment cut) through the
worktree loop, exactly as `run` lands a feature; the only difference is that the
diff is all deletions:

```bash
WT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" add garden/<slug>)
```

`cd "$WT"`, make the cut, then **verify**:

- Run the full suite through the serialized wrapper:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" verify` (background it and poll,
  since a full suite outlasts the foreground timeout). Green means the cut was safe.
- **Red means the cut is wrong**: the "dead" thing was load-bearing. Discard the
  worktree (`worktree.sh remove`), and record the finding as a judgment item:
  something depends on it that the scan didn't see. Never weaken a test to make a
  cut land.
- Then commit in `$WT` with a Conventional Commits message whose body carries the
  **`Cut:` line** naming exactly what was removed, and land it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" land garden/<slug>
```

Read the land exit as `run` does (0 landed; 6 regressed and rolled back → the cut
was unsafe, treat as red above; 9 conflict → another change owns these files, defer;
7/8 → a land gate wants a human, escalate). Independent cuts may run in parallel
worktrees; land them one at a time.

## 4. Judgment — the consolidate-critic, repo-wide

For the judgment findings, hand the `consolidate-critic` a **constructed brief**
(the durable lines in question, the code they claim to govern, the relevant Notes
and Decisions), never your own scan transcript. It is prompted to argue for the
cut. Apply its accepted cuts as deletion-only changes (step 3); for a cut it can't
justify, leave the line. A Decision the critic defends stays.

Anything that needs a human call (a Decision that may be stale but only the owner
knows, a Note whose invariant you can't confirm) is **logged, never guessed at**:
a `docs/open-questions.md` entry, or an escalation. `garden` never deletes
recorded rationale just to have a cut to show.

## 5. Report — what was cut, what was deferred

Close with the ledger: each cut landed (and its `Cut:` line), each finding
abandoned because the suite went red (with what it revealed depends on it), and
each judgment item deferred to a human. A garden run that cut nothing is a valid
outcome: say so, and do not manufacture a cut to look busy. Silent truncation
(a scan that stopped early, a cut skipped without a reason) reads as "clean" when
it isn't, so name every skip.

## Budget and scope

`garden` is unbounded work over a whole repo, so cap it: scan fully, but land the
highest-confidence cuts first and stop at a sensible batch rather than churning
dozens of merges in one run. What you defer is named in the report and picked up
next run. The loop is meant to run **often and small**: a scheduled trickle of
cuts.

## Scheduling

hone does not own a scheduler. Run `garden` on whatever cron/CI the project
already has, as a print-mode user turn (the same nesting `run` uses for
`/code-review`):

```bash
claude -p "/hone:garden" --model opus --effort high --output-format json
```

Point it at the primary tree; each cut still lands through the worktree loop and
the land lock, so a scheduled `garden` and an interactive `run` never collide.
