---
name: run
description: "Execute one or more Plans unattended through the hone loop: worktree, build (test-first), verify, consolidate, /code-review, land. Confirms each step by its artifacts, never a subagent's report; proceeds without checking in and stops only when blocked-unresolvable, genuinely ambiguous, or done, leaving the worktree as evidence. Invoke with /hone:run [change | --all]."
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
whose artifact does not confirm it.** The two points at which you stop and
escalate are marked; on either of them, leave the worktree in place as evidence
and report. Never disable a gate to get past it.

Admission already happened: the `plan-critic` admitted the Plan at `/hone:plan`,
with the human present to revise a rejection. Do not re-run it here; spawn the
worktree and build.

### 1. Worktree

Spawn an isolated worktree and work in it for every step below:

```bash
WT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" add <change>)
```

That creates `.worktrees/<change>` on branch `hone/<change>` and prints its path.
`cd "$WT"`. All build/verify/consolidate work happens here; the primary tree is a
merge target and the `guard` will block durable edits made in it.

The worktree **is the change's claim**, and the add is atomic: if it exits **4**,
this change is already claimed — another `run` (in another session) owns it, or a
crashed run left it behind. Do **not** adopt that worktree: a single named change
**stops** and reports it (the human resumes leftover work by hand); under `--all`
it is **skipped** (below). Only exit 0 means you own this change and may proceed.

### 2. Build — red → green, serial

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

An **unrelated defect discovered en route** (broken tooling, a latent bug the
Plan never mentioned) does not ride inside the change's commit. Fix it with its
own red-green cycle and its **own commit on the branch**, honestly typed — or,
if it is substantial, stop and escalate for its own Plan. The landing commit's
body still notes the discovery; the fix just doesn't hide in an unrelated diff.

Where the Plan names a critical path, prefer a **property test** for any
universal invariant (`parse(serialize(x)) == x`) alongside the example tests.

### 3. Verify

- **gate**: run the full suite through the serialized wrapper —
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" verify` — never the adapter
  bare with `--all`. Full-suite runs share one cross-session lock with land:
  e2e tiers are load-sensitive, so a suite racing another session's suite or
  land produces phantom flakes and spurious rollbacks, and the wrapper waits
  its turn instead. (Per-file and unit-tier runs during build need no wrapper.)
  Then, if present, `scripts/typecheck.sh` and `scripts/lint.sh`. All must be
  green. (The Stop-hook gate also enforces this; running it here is how *you*
  confirm, from the output, not from having intended it. On a clean, committed
  `hone/<change>` branch the gate itself escalates to `--all` under the same
  lock, so an integration regression can't merge on a green unit tier alone;
  while the tree is dirty it runs the fast unit tier.) A full suite can outlast
  the ~2m foreground Bash timeout, which kills it regardless of any inner
  `timeout`; run the gate — and any long build or verify command — in your Bash
  tool's background mode and poll it to completion, never in the foreground where
  a kill reads as a spurious failure.
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
(stop-point 1), leaving the worktree as evidence.

### 4. Consolidate — route residue, prune, delete the Plan

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
- **delete `.plans/<change>.md` — in the primary tree.** `.plans/` is
  gitignored, so it exists only there; the worktree checkout has no copy and an
  `rm` from `$WT` fails on a path that was never here. Use `rm -f` from the
  primary tree and tolerate the file already being gone (a parallel run's
  cleanup may have raced you — that is not lost work). The Plan has done its
  job. A nested slug leaves empty parent dirs behind — remove those too
  (`rmdir -p .plans/<area> 2>/dev/null`, also in the primary tree).

Then submit the change to the `consolidate-critic` agent (Task tool,
`subagent_type: consolidate-critic`) with a constructed brief: the diff, the
Plan (still in hand), and the Decisions/Notes touched. It is prompted to argue
for deletion: a Decision restating code, a Note drifting into a spec, a
redundant test, an abstraction not earning its keep. Apply its accepted findings
(more pruning), or record why not.

### 5. Review — native `/code-review`

Run Claude Code's `/code-review` on the finished change (the worktree diff)
**once** — it is multi-agent (parallel finders plus a verification pass) and the
loop's most expensive step, so it runs a single time and hone reuses it rather
than shipping a reviewer. Like the critics, it gets a constructed brief: pass
the Plan text (still in hand — the file is gone) along with the diff, so the
reviewer can tell a violation of the Plan's stated stance from the stance
itself.

The built-in `/code-review` is now **user-invocation-only** (`disable-model-invocation`):
the Skill tool refuses it — `Skill code-review cannot be used with Skill tool due
to disable-model-invocation` — as does every other model-invocation path (a
SlashCommand tool, a subagent). The refusal is **expected**, not a dead end: when
you see it, your one and only next move is the nested `claude -p` call below.
Do **not** hand-roll a substitute reviewer — no `Workflow`, no fan-out of
`Agent`/`Task` finders, no "faithful equivalent" or "same multi-agent shape"
you assemble yourself. Every one of those silently abandons the native review
(parallel finders plus a verification pass) this step exists to reuse, and is a
step failure even when it produces findings. The Skill tool is not your only path
to the command; a `claude -p` user turn is.

The flag blocks the *model* from invoking the command, not a *user*. A slash
command in a print-mode (`-p`) prompt is a user invocation, so run the genuine
native reviewer unattended by nesting a headless Claude Code. Write the brief to
a file, then invoke it with the worktree as the working directory so the
command's own `git diff` sees the local change. The multi-agent fan-out takes
several minutes — longer than the foreground Bash timeout, which kills it at ~2
minutes regardless of any inner `timeout` — so **run it in the background** (your
Bash tool's background mode, not a shell `&`, which the harness won't keep
alive), redirect the JSON to an output file, and poll that file until the run
finishes:

```
claude -p "/code-review $(cat <brief-file>)" \
  --add-dir <worktree> \
  --allowedTools "Task Agent Read Grep Glob Bash(git *)" \
  --model opus --effort high \
  --output-format json > <out-file> 2>&1
```

That JSON envelope **is this step's artifact** — the proof the native reviewer
ran, exactly as the diff proves build and the gate output proves verify. Before
you trust any finding, confirm the envelope is real: `<out-file>` parses as JSON
with `is_error: false`, `subtype: success`, and a `session_id`. If it is missing,
truncated, an error envelope, or absent because you produced findings some other
way, the native review **did not happen** — that is a step failure to fix by
running the nested call, never a pass to review around. Only once the envelope
confirms do you read the review from its `.result` and feed it into the triage
below. The `--allowedTools` allowlist lets the reviewer's finders fan out
without granting full `bypassPermissions` (a trivial diff reviews cleanly even
in the default mode, but the heavy fan-out wants its tools). Do **not** locate,
read, or execute a command file on disk, and do not add a marketplace
`code-review` plugin to the path: that plugin is GitHub-PR-shaped (it wants a PR
number and `gh pr comment`) and does not fit a worktree. A literal
`/code-review` in the nested session resolves deterministically to the built-in
command — but a fuzzy skill lookup or disk search can still land on the decoy
and make the review balk.

Triage its findings against the Plan:

- **Apply** confirmed findings with red-green cycles (never a fix without a
  test); those fixes are re-gated by `verify`, not by a second review.
- **Decline** a confirmed finding only when it contradicts the Plan's explicit
  stance or falls outside the change's scope — and record every decline
  durably, in the landing commit's body or (for a real defect deferred, not
  dismissed) as a `docs/open-questions.md` entry. A decline that lives only in
  the conversation is lost to the next cycle.

Triage is yours — never pause to ask how many findings to apply; `run` is
unattended and a scope question is not a genuine fork. The default: apply every
confirmed finding inside the Plan's scope, and record out-of-scope ones
durably as follow-up material (a `docs/open-questions.md` entry, or a note in
the landing commit body suggesting a future Plan) rather than expanding the
change or blocking on a human.

If the review surfaces something that makes the change genuinely ambiguous or
wrong to land — not merely large or out of scope — **stop and escalate**
(stop-point 2).

### 6. Land

Commit in the worktree, then hand the merge to `worktree.sh land`:

1. In `$WT`: `git add -A && git commit` with a Conventional Commits message. The
   Decision(s) this change governs land in **this same commit** as the code.
   The **type follows the dominant durable artifact**: a change that alters the
   behaviour of `deploy/` or `scripts/` is never `docs:`, whatever prose rode
   along. The body carries a **`Cut:` line** naming what consolidate removed
   (pruned tests, dead code, deleted doc lines) — or `Cut: nothing`, with the
   reason, when there genuinely was nothing; the nag flags a zero-deletion
   change, and this line is its answer.
2. From the primary tree, land the branch:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" land <change>
   ```

   That takes the **land lock**, so it is safe even when another `run` is
   landing into the same primary tree at the same time — it waits its turn
   instead of interleaving. Under the lock it merges `--no-ff`, **re-runs the
   whole suite** in the primary tree (green confirms the merge — the
   confirmation is the suite, not the merge succeeding), and on green removes
   the worktree and deletes the branch. Read its exit:
   - **0** — landed and green.
   - **6** — the merge regressed the trunk; `land` rolled it back (the primary
     tree is left green) and kept the worktree as evidence. **Stop and
     escalate** (this is stop-point 1 surfacing at land).
   - **2** — a merge conflict (aborted, tree restored) means the `--all`
     independence check missed a seam: fold this change in serially and flag it
     for a Decision-level look. Do not force the merge.

   Never merge by hand, and never move the primary tree's HEAD
   (`git checkout`/`switch`/`stash`/`reset`) to investigate — that races every
   other session sharing the tree, and the `bash-guard` will stop you. The
   primary tree stays on the trunk as a merge target; do any investigation in a
   throwaway `git worktree add --detach` scratch tree.

Confirm to the user: what landed, the Decisions/Notes written, what was deleted
(the Plan, and any pruned tests; every cycle removes something).

## `--all` — many changes at once

Parallelism is `run` over several Plans, not a special mode — and it is never
assumed. **Check independence first, before spawning any worktree.** Each
`plan-critic` ran at plan time, before later Plans existed; this is the first
moment the whole set is visible, so the cross-check is yours.

Read every ready Plan and compare them pairwise: the files and areas each
expects to change (its *Notes for the loop*, its *What*, a quick look at
`src/`), any shared type or persistent contract (a DB schema, a public API, a
wire or file format), and any Decision or Note more than one would touch. Then
partition:

- **Disjoint Plans** run in parallel: steps 1–5 each in its own worktree,
  concurrently.
- **Overlapping Plans** run sequentially: order them (foundation first — the
  Plan the others build on), and run each fully through step 6 before starting
  the next, so the later change builds on the landed result instead of fighting
  it at the merge. Sequencing is your call; it needs no escalation.

State the partition and its reason before starting ("`a` and `b` are disjoint —
parallel; `c` touches the same schema as `a` — after `a` lands").

A change whose `add` exits **4** is already claimed by another `run` sharing this
repo — **skip it** and note the skip in the partition report; never adopt its
worktree. This is what keeps two concurrent `/hone:run` invocations from both
building the same Plan: the worktree is a single atomic claim.

Then **land them one at a time** through step 6:

- Lands are serialized by the land lock even across sessions, so `worktree.sh
  land` never interleaves two merges; within this run, still drive them one at a
  time so each builds on the last landed result.
- The upfront check is a judgment; the **merge verifies it**. A merge collision
  on a shared type, Decision, or Note (`land` exit 2) means the check missed a
  seam: fold it into one serial change and flag it for a Decision-level look. Do
  not force the merge.
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
