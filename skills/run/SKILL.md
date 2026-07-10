---
name: run
description: "Execute one or more Plans unattended through the hone loop: admission, worktree, build (test-first), verify, consolidate, /code-review, land. Confirms each step by its artifacts, never a subagent's report; proceeds without checking in and stops only when blocked-unresolvable, genuinely ambiguous, or done, leaving the worktree as evidence. Invoke with /hone:run [change | --all]."
argument-hint: "[change-name | --all]"
disable-model-invocation: true
---

# /hone:run — execute a Plan through the loop

Input: $ARGUMENTS

`run` is the automatic half of hone. Given a Plan it drives the whole loop and
lands the change green, unattended. It reports each step's completion from that
step's **artifacts** (the diff, the gate output, the review verdict), never from
a subagent's claim that it finished.

Resolve `$ARGUMENTS`:

- `<change>`: run the single Plan `.plans/<change>.md`.
- `--all`: run every ready Plan in `.plans/`, each in its own worktree, landing
  them one at a time (below).
- empty: list the Plans in `.plans/`; if exactly one, run it; else ask which.

Setup check: if `scripts/run-tests.sh` is missing, stop and tell the user to run
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"` first; without the adapter the
gate can't verify anything.

## The loop, per Plan

Run these steps in order. **Do not skip a step, and do not proceed past a step
whose artifact does not confirm it.** The three points at which you stop and
escalate are marked; on any of them, leave the worktree in place as evidence and
report. Never disable a gate to get past it.

### 1. Admission — `plan-critic`

Before spawning anything, submit the Plan to the `plan-critic` agent (Task tool,
`subagent_type: plan-critic`). Give it a **constructed brief**: the Plan text,
the list of open changes (other `.plans/**/*.md` — slugs nest — and existing
`hone/*` worktrees),
and the relevant existing Decisions/Notes, never your own transcript. It returns
structured findings.

**If it rejects** (placeholder, contradiction, ambiguity, wrong scope, or
collision with an open change): **stop and escalate** to the human with the
findings. Do not spawn a worktree, do not "fix" the Plan yourself; the human owns
the Plan. This is stop-point 1.

### 2. Worktree

Spawn an isolated worktree and work in it for every step below:

```bash
WT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" add <change>)
```

That creates `.worktrees/<change>` on branch `hone/<change>` and prints its path.
`cd "$WT"`. All build/verify/consolidate work happens here; the primary tree is a
merge target and the `guard` will block durable edits made in it.

### 3. Build — red → green, serial

Implement the Plan test-first, one behaviour at a time. The `guard` enforces the
order, so work with it:

- **Type first.** Anything expressible as a type (a shape, a constraint, an
  illegal state made unrepresentable) is a type, not prose or a runtime check.
- **Red.** Write one failing test that pins an observable behaviour from the
  Plan's *How I'll know it works*. Run it via `scripts/run-tests.sh <file>` and
  **watch it fail for the right reason.** A test that passes on first run is
  test-after: the code was written first or the test asserts nothing; discard
  and rewrite it.
- **Green.** Write the minimum code to pass it. Run the same file; it passes.
- **Refactor.** Clean up what you just wrote; run `scripts/run-tests.sh` (unit
  tier); all green.
- Repeat for the next behaviour. The loop is **serial**: each cycle learns from
  the last; never parallelise cycles within a change.

A bug fix is the same loop: the first red test *reproduces the defect*, then you
fix the root cause. Never fix first and add a confirming test after.

Where the Plan names a critical path, prefer a **property test** for any
universal invariant (`parse(serialize(x)) == x`) alongside the example tests.

### 4. Verify

- **gate**: run `scripts/run-tests.sh --all` and, if present,
  `scripts/typecheck.sh` and `scripts/lint.sh`. All must be green. (The Stop-hook
  gate also enforces this; running it here is how *you* confirm, from the output,
  not from having intended it. On a clean, committed `hone/<change>` branch the
  gate itself escalates to `--all`, so an integration regression can't merge on a
  green unit tier alone; while the tree is dirty it runs the fast unit tier.)
- **nag**: no leftover Plan yet (that's consolidate), but check Notes you touched
  are within size and 1:1 with an area.
- **mutation check on critical paths only**. For a critical path the Plan names,
  seed-and-catch: run your ecosystem's mutation runner (StrykerJS for JS/TS;
  mutmut or cosmic-ray for Python), **diff-scoped and budget-capped**, isolated so
  it never touches the tree. It audits the *tests*, not the code. A surviving
  mutant means a hollow test; close the gap with another red-green cycle. Skip it
  for non-critical or UI changes; never gate a trivial change on it.

Close verify by stating each check's outcome — tests, type-check, lint,
mutation — including any skip **with its reason** ("mutation: skipped — no
critical path named in the Plan"). An unstated skip is indistinguishable from a
forgotten check, and this receipt is what a later audit of the transcript reads.

If verify cannot go green and you have exhausted the fix, **stop and escalate**
(stop-point 2), leaving the worktree as evidence.

### 5. Consolidate — route residue, prune, delete the Plan

This is the only step that writes `docs/` and the only step that prunes tests.
Route each piece of durable residue to where it can't rot, applying the **cut
test** (never write a line an agent could recover from the code; if it can be a
type, it already became one at build):

- an intent or invariant the code can't show → a **Note** (`docs/notes/<area>.md`,
  a map + one invariant, size-capped, 1:1 with an area);
- a decision + why (and a rejected alternative, if load-bearing) → a **Decision**
  (`docs/decisions/<topic>.md`, present-tense, one per topic, edited in place);
- a resolved empirical bet → **close** its `docs/open-questions.md` entry;
- redundant tests the change revealed → **prune** them (deduplication is a real
  output of this step, not an afterthought).
- **delete `.plans/<change>.md`.** The Plan has done its job.

Then submit the change to the `consolidate-critic` agent (Task tool,
`subagent_type: consolidate-critic`) with a constructed brief: the diff, the
Plan (still in hand), and the Decisions/Notes touched. It is prompted to argue
for deletion: a Decision restating code, a Note drifting into a spec, a
redundant test, an abstraction not earning its keep. Apply its accepted findings
(more pruning), or record why not.

### 6. Review — native `/code-review`

Run Claude Code's `/code-review` on the finished change (the worktree diff)
**once** — it is multi-agent (parallel finders plus a verification pass) and the
loop's most expensive step, so it runs a single time and hone reuses it rather
than shipping a reviewer. Like the critics, it gets a constructed brief: pass
the Plan text (still in hand — the file is gone) along with the diff, so the
reviewer can tell a violation of the Plan's stated stance from the stance
itself.

Triage its findings against the Plan:

- **Apply** confirmed findings with red-green cycles (never a fix without a
  test); those fixes are re-gated by `verify`, not by a second review.
- **Decline** a confirmed finding only when it contradicts the Plan's explicit
  stance or falls outside the change's scope — and record every decline
  durably, in the landing commit's body or (for a real defect deferred, not
  dismissed) as a `docs/open-questions.md` entry. A decline that lives only in
  the conversation is lost to the next cycle.

If the review surfaces something that makes the change genuinely ambiguous or
wrong to land, **stop and escalate** (stop-point 3).

### 7. Land

Commit in the worktree, then merge into the primary tree and verify there:

1. In `$WT`: `git add -A && git commit` with a Conventional Commits message. The
   Decision(s) this change governs land in **this same commit** as the code.
2. From the primary tree, merge the branch (`git merge --no-ff hone/<change>`).
3. **Re-run the whole suite in the primary tree**: `scripts/run-tests.sh --all`.
   Green confirms the merge; this is the confirmation, not the merge succeeding.
4. Remove the worktree:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" remove "$WT"`.

Confirm to the user: what landed, the Decisions/Notes written, what was deleted
(the Plan, and any pruned tests; every cycle removes something).

## `--all` — many changes at once

Parallelism is `run` over several Plans, not a special mode. For each ready Plan,
run steps 1–6 in its own worktree (these are independent and may proceed
concurrently). Then **land them one at a time** through step 7:

- Independence was the human's judgement; the **merge verifies it**. A merge
  collision on a shared type, Decision, or Note *disproves* independence: fold
  that seam into one serial change and flag it for a Decision-level look. Do not
  force the merge.
- After all merges, run one **global consolidate pass** (a `consolidate-critic`
  over the combined result) to catch cross-change duplication no single worktree
  could see.

## The three ways to stop

`run` proceeds without checking in. It stops only when:

1. **blocked with no resolution**: a gate won't go green and the fix is
   exhausted;
2. **genuinely ambiguous**: the Plan or the review leaves a real fork only the
   human can pick;
3. **done**: landed and green.

On 1 or 2, leave the worktree in place as evidence and escalate with the specific
blocker. Never disable, weaken, or route around a gate to proceed: an escalated
stop is a correct outcome, a forced pass is not.
