---
name: run
description: "Execute one or more Plans unattended through the hone loop: worktree, build (test-first), verify, consolidate, /code-review, land. Confirms each step by its artifacts, never a subagent's report; proceeds without checking in and stops only when blocked-unresolvable, genuinely ambiguous, or done, leaving the worktree as evidence. Inside herdr, --all spreads the Plans over tabs by itself: this session orchestrates, and each Plan runs in a fresh session in its own tab. Invoke with /hone:run [change | --all] [--model <model>]."
argument-hint: "[change-name | --all] [--model <model>]"
---

# /hone:run (execute a Plan through the loop)

Input: $ARGUMENTS

`run` is the automatic half of hone. Given a Plan it drives the whole loop and
lands the change green, unattended. It reports each step's completion from that
step's **artifacts** (the diff, the gate output, the review verdict), never from
a subagent's claim that it finished.

Resolve `$ARGUMENTS`:

- `<change>`: run the single Plan `.plans/<change>.md`.
- `--all`: run every ready Plan in `.plans/`, each in its own worktree, landing
  them one at a time (below).
- empty: list the Plans in `.plans/`. If exactly one, run it. Otherwise ask which.
- `--model <model>`: the model for the sessions `--all` spawns inside herdr
  (below). It changes nothing about a run in this session. The default is
  `opus`. Never select `fable` yourself. The loop needs the stronger model.
  Use `fable`, or any other model, only when the user asks for it by name.

Setup check: if `scripts/run-tests.sh` is missing, stop and tell the user to run
`/hone:setup` first. Without the adapter the gate can't verify anything.

## Reporting: the four kinds of output

Everything `run` prints is one of four kinds, and each kind has a fixed shape.
The shape is what lets a reader tell a status update from a receipt, and see
where the run stands.

**The progress line.** The steps form a fixed chain:
`worktree > build > verify > consolidate > review > land`. Print the chain as
one line when a step starts and again when it ends. Open the line with the
marker `◆` and the change name, each wrapped in backticks. Mark a finished
step `✓`, the active step `...`, and a failed step `✗`. Leave a step not yet
reached bare.

Backticks also wrap exactly one step: the step where the run stands. That is
the active step while the run works, and the failed step on a stop. After the
run lands, it is the land step with its receipt. The terminal renders a backticked
span in the inline-code color, so the highlight shows where the run stands at
a glance. Print the line as plain markdown, never inside a code fence. A fence
stops that rendering. A mid-run line looks like this:

`◆` `[csv-export]` worktree ✓ > build ✓ > `verify ...` > consolidate > review > land

When a step ends, its `✓` carries that step's artifact in short form, in
parentheses. Earlier steps keep a bare `✓`:

`◆` `[csv-export]` worktree ✓ > build ✓ > verify ✓ (suite 212/212, typecheck ✓,
lint ✓, mutation: skipped, no critical path named) > `consolidate ...` > review > land

On a stop, the highlight sits on the failed step:

`◆` `[csv-export]` worktree ✓ > `build ✗` > verify > consolidate > review > land

After the run lands, the highlight rests on land:

`◆` `[csv-export]` worktree ✓ > build ✓ > verify ✓ > consolidate ✓ > review ✓ >
`land ✓ (merged 3f2a1c9)`

That annotated `✓` **is** the step's receipt. It states outcomes read from the
artifact. It names every skipped check with its reason, because an unstated
skip looks like a forgotten check. A line with no artifact is a status update,
never a completion claim.

**Status updates.** Between progress lines, narrate in plain one-sentence
present tense ("Running the full suite in the background."). No checkmarks and
no headers: those belong to progress lines and the final report.

**Quoted subagent output.** Findings from the `consolidate-critic` or from
`/code-review` are someone else's claims until you triage them. Frame them.
Open with one line that names the source ("consolidate-critic findings, before
triage:"). Close with your own verdict ("Triage: applied 2. Declined 1, recorded
in the commit body."). Never let a quoted finding stand as if it were the run's
own conclusion.

**The final report.** Every run ends with one block in this shape, whatever the
outcome:

```
## <change>: landed | stopped at <step>

- Outcome: <the merge commit, or the blocker>
- Cut: <what consolidate removed, or "nothing" with the reason>
- Docs: <Decisions/Notes written, open questions closed, or "none">
- Declined: <review findings declined + where recorded, or "none">
- Next: <"nothing" | the check the human must run | the fork to decide>
```

On a stop, the last progress line (with its `✗`) sits directly above this
block. The reader then sees where the run stopped and why in one place.

## The loop, per Plan

Three hooks enforce the laws as you work. The first is the `guard` (PreToolUse:
test-first, and no durable edits in the primary tree). The second is the `gate`
(Stop: the suite, type-check, and lint stay green). The third is the `nag`
(Stop, advisory: Plan and Note hygiene).

Run these steps in order. **Do not skip a step, and do not proceed past a step
whose artifact does not confirm it**. Where a step can end the run instead of
feeding the next, *The three ways to stop* at the end says how.

The Plan check already happened: the `plan-critic` approved the Plan at
`/hone:plan`, with the caller present to revise a rejection. Do not re-run it
here. Spawn the worktree and build.

### 1. Worktree

Spawn an isolated worktree and work in it for every step below:

```bash
WT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" add <change>)
```

That creates `.worktrees/<change>` on branch `hone/<change>` and prints its path.
When the project ships `scripts/setup-tree.sh`, `add` has already run it in the
new worktree, so dependencies are installed before the first verify. A failed
adapter is exit 2 with the worktree kept: fix the install, never adopt the red
as a build failure.
`cd "$WT"`. All build/verify/consolidate work happens here. The primary tree is a
merge target and the `guard` will block durable edits made in it.

**Address every file you edit as `$WT/<path>`.** That `cd` moves the shell only.
The file tools still resolve a bare `scripts/foo.sh` against the primary tree.
A relative path therefore edits the wrong file. The settings deny rules refuse
it there, and that refusal reads like a ban on the work itself. It is not one.
The loop may author a change to `scripts/proof.sh` in the worktree. `land` then
gates that change for the human (step 6, exit 7).

Creating the worktree is what **claims the change**, and the creation is atomic.
Exit **4** means the change is already claimed: another `run` (in another
session) owns it, or a crashed run left it behind. Do **not** adopt that
worktree. A single named change **stops** and reports it (the human resumes
leftover work by hand). Under `--all` it is **skipped** (below). Only exit 0
means you own this change and may proceed.

### 2. Build: red → green, serial

If the Plan has a *References* section, **read every file it names before writing
anything**. A reference is there because prose would have lost the detail: a
fixture of input/expected rows, a sample payload, a mockup, an existing schema.
Where one pins data a test needs, have the test **read the file** rather than
transcribing its contents into assertions. The transcription is what goes stale.
Move it into place beside that test as part of the same red-green cycle
(`git mv .plans/<change>/cases.csv src/export/__fixtures__/cases.csv`). From
then on it is a test artifact like any other, and the suite is what keeps it
honest.

If a named reference does not exist, **stop**, and never invent its contents. The
plan step commits references together with the Plan, so a missing one means the
hand-off broke.

Implement the Plan test-first, one behaviour at a time. The `guard` enforces the
order, so work with it:

- **Type first**. Anything expressible as a type (a shape, a constraint, an
  invalid state made impossible to express) is a type, not prose or a runtime
  check.
- **Red.** Write one failing test that pins an observable behaviour from the
  Plan's *How I'll know it works*. Run it via `scripts/run-tests.sh <file>` and
  **watch it fail for the right reason**. A test that passes on first run is
  test-after. Either you wrote the code first, or the test asserts nothing.
  Discard and rewrite it.
- **Green.** Write the minimum code to pass it. Run the same file. It passes.
- **Refactor.** Clean up what you just wrote. Run `scripts/run-tests.sh` (unit
  tier). All green.
- Repeat for the next behaviour. The loop is **serial**: each cycle learns from
  the last. Never parallelise cycles within a change.

A bug fix is the same loop: the first red test *reproduces the defect*, then you
fix the root cause. Never fix first and add a confirming test after.

A **dependency or toolchain refresh** is the exception, and it has its own shape.
A version bump has no failing test to write first. Its evidence is the suite
at the Plan's counts plus checks the gate cannot make. Read
`references/dependency-refresh.md` before the first cycle whenever the change
bumps a version, and follow its build and verify steps.

An **unrelated defect discovered en route** (broken tooling, a latent bug the
Plan never mentioned) does not ride inside the change's commit. Fix it with its
own red-green cycle and its **own commit on the branch**, honestly typed. If it
is substantial, stop and escalate for its own Plan. The landing commit's
body still notes the discovery. The fix just doesn't hide in an unrelated diff.

Where the Plan names a critical path, prefer a **property test** for any
universal invariant (`parse(serialize(x)) == x`) alongside the example tests.

### 3. Verify

- **gate**: the full suite, plus type-check and lint, all green:
  - Run the full suite through the serialized wrapper:
    `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" verify`. Never run the
    adapter bare with `--all`. Full-suite runs share one cross-session lock with
    land, because e2e tiers are load-sensitive. A suite racing another
    session's suite or land produces phantom flakes and spurious rollbacks. The
    wrapper waits its turn. (Per-file and unit-tier runs during build need no
    wrapper.)
  - Then run `scripts/typecheck.sh` and `scripts/lint.sh` if present. All must be
    green.
  - Run the gate here so you can confirm each check from its output, not from
    having intended to run it. The Stop-hook gate enforces the same suite
    independently. On a clean, committed `hone/<change>` branch it escalates to
    `--all` under the same lock (so an integration regression can't merge on a
    green unit tier alone). While the tree is dirty it runs the fast unit tier.
  - A full suite can outlast the ~2m foreground Bash timeout, which kills it
    regardless of any inner `timeout`. Run the gate (and any long build or verify
    command) in your Bash tool's background mode, and poll it to completion.
    Never run it in the foreground, where a kill reads as a spurious failure.
- **nag**: no leftover Plan yet (that's consolidate), but check Notes you touched
  are within size and 1:1 with an area.
- **mutation check on critical paths only**. For a critical path the Plan names,
  run a mutation check with your ecosystem's runner (StrykerJS for JS/TS,
  mutmut or cosmic-ray for Python). It plants small bugs on purpose and confirms
  a test catches each one. Run it **diff-scoped and budget-capped**, isolated so
  it never touches the tree. It audits the *tests*, not the code. A planted bug
  no test catches means a test that checks too little. Close the gap with
  another red-green cycle. Skip it
  for non-critical or UI changes. Never gate a trivial change on it.

Close verify with its progress line. Each check's outcome (tests, type-check,
lint, mutation) goes in the verify `✓`'s artifact. Include any skip **with
its reason** ("mutation: skipped, no critical path named in the Plan"). An
unstated skip is indistinguishable from a forgotten check, and this receipt is
what a later audit of the transcript reads.

If verify cannot go green and you have exhausted the fix, **stop and escalate**
(stop-point 1), leaving the worktree as evidence.

### 4. Consolidate: sort the leftovers, prune, delete the Plan

This is the only step that writes `docs/` and the only step that prunes tests.
Sort everything the change leaves behind that is worth keeping into the place
where it can't go stale, applying the **cut test**. Never write a line an agent
could recover from the code. If it can be a type, it already became one at
build.

- an intent or invariant the code can't show → a **Note** (`docs/notes/<area>.md`,
  a map + one invariant, size-capped, 1:1 with an area).
- a decision + why (and a rejected alternative, if load-bearing) → a **Decision**
  (`docs/decisions/<topic>.md`, present-tense, one per topic, edited in place).
- an assumption running code has now settled → **close** its
  `docs/open-questions.md` entry.
- an assumption this change's proof run has **not** settled yet → **leave** its
  `docs/open-questions.md` entry open, and write no Decision that states or
  predicts the answer. A Decision states what is settled. The open question
  holds the rest, and consolidate stays silent on it. A change whose Plan
  carries a `Proof: real-environment` line can never report its own proof
  result here, because that proof runs at land, after this step. So a forecast
  written now reads as a finding later, and nothing in the loop comes back to
  correct it.
- an investigation whose method or dead ends outlive its conclusion → a
  **spike**, kept whole under one dated stem,
  `docs/spikes/<YYYY-MM-DD>-<slug>`. It holds the probe code, whatever it
  captured, and a note at `<YYYY-MM-DD>-<slug>.md` from
  `${CLAUDE_PLUGIN_ROOT}/templates/spike-note.md`. Write the note once, in the
  past tense, pointing forward to the Decision or Note that now carries the
  finding. This is rare, and the bar is high: the usual outcome of a probe is a
  Decision plus a deleted probe, with nothing kept. Never write one to record
  what the change does, which is what the code and the tests already carry.
- redundant tests the change revealed → **prune** them (deduplication is a real
  output of this step, not an afterthought).
- **delete `.plans/<change>.md` with `git rm`, here in the worktree.** The Plan
  is tracked and committed on the trunk, so the worktree checked it out. Remove
  it as part of this change (`git rm .plans/<change>.md` from `$WT`). The
  landing merge carries the deletion back to the primary tree. git history keeps
  the Plan. The working tree does not. The Plan has done its job. (Already gone,
  because you git-rm'd it earlier? Fine, do not re-add it.)
- **`git rm` whatever is left under `.plans/<change>/`.** Build already moved the
  references the tests read into the tree beside those tests. Anything still
  sitting here only communicated intent (a mockup, a sample payload nothing
  loads) and is finished, like the Plan itself. Delete it, and
  `.plans/<change>/` with it: a reference directory that survives the merge
  becomes exactly the kind of stale prose hone exists to remove. (A reference
  that named a path already in the repo was never yours and needs nothing.)

Then submit the change to the `consolidate-critic` agent (Task tool,
`subagent_type: consolidate-critic`) with a constructed brief: the diff, the
Plan (still in hand), and the Decisions/Notes touched. It is prompted to argue
for deletion. Its targets are a Decision restating code, a Note drifting into a
spec, a redundant test, an abstraction not earning its keep. Apply its accepted
findings (more pruning), or record why not.

### 5. Review: native `/code-review`

First ask the diff how deep its review must go:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" review-scope <change>
```

It prints one word.

- **`full`**: the answer for every change that touches code. Run the review below.
- **`docs-only`**: the diff changes nothing outside `docs/` and `.plans/`, so a
  code reviewer has no code to read. Skip the review and go to *land*. State
  the skip and the word the script printed in the review `✓`'s artifact
  ("review ✓ (skipped, review-scope: docs-only)"). Do it exactly as verify
  states a skipped mutation check. The `consolidate-critic` already judged this
  change at step 4, and prose is what it judges.

Read that word. Never form your own view of it. "This change looks too small to
review" is not yours to decide, and a five-line change to a critical path still
gets the full review. The word is the only input, and anything the script cannot
classify comes back `full`.

Run Claude Code's built-in `/code-review` on the finished change (the worktree
diff) **once**. It is multi-agent (parallel finders plus a verification pass) and
the loop's most expensive step. So it runs a single time, and hone reuses it rather
than shipping a reviewer. Give it a constructed brief. Pass the Plan text (still in
hand, the file is gone) along with the diff. The reviewer can then tell a violation
of the Plan's stated stance from the stance itself.

The command is **user-invocation-only** (`disable-model-invocation`), so the Skill
tool, a SlashCommand tool, and subagents all refuse it. That refusal is
**expected**, and the nested call below is the one and only next move. A slash
command in a print-mode (`-p`) prompt is a *user* invocation. Write the brief to a
file. Run it in your Bash tool's background mode (not a shell `&`) and poll
the output file, because the fan-out outlasts the ~2m foreground timeout:

```
claude -p "/code-review $(cat <brief-file>)" \
  --add-dir <worktree> \
  --allowedTools "Task Agent Read Grep Glob Bash(git *)" \
  --model opus --effort high \
  --output-format json > <out-file> 2>&1
```

That JSON envelope is this step's **proof that the review ran**. Before you
trust any finding, confirm `<out-file>` parses as JSON with `is_error: false`,
`subtype: success`, and a `session_id`. Anything else (missing, truncated, an
error envelope, or findings you produced some other way) means the native
review did not happen.
Fix that by running the nested call. Never review around it. Never hand-roll a
substitute (no `Workflow`, no fan-out of `Agent`/`Task` finders). A substitute
abandons the very review this step exists to reuse, and it fails the step even
when it produces findings.

`references/code-review.md` carries the rest: why the refusal happens, why a
substitute fails, the envelope details, and the marketplace-plugin decoy to avoid.
Read it if this step misbehaves.

Triage its findings against the Plan. Triage is yours: `run` is unattended and a
scope question is not a genuine fork, so never pause to ask how many findings to
apply.

- **Apply** every confirmed finding inside the Plan's scope, with red-green
  cycles (never a fix without a test). `verify` re-gates those fixes, not a
  second review.
- **Decline** a confirmed finding only when it contradicts the Plan's explicit
  stance or falls outside the change's scope. Record the decline **durably**:
  the landing commit body, or a `docs/open-questions.md` entry for a real defect
  deferred rather than dismissed. That is how an out-of-scope finding becomes
  follow-up material instead of expanding the change. A decline that lives only in
  the conversation is lost to the next cycle.

If the review surfaces something that makes the change genuinely ambiguous or
wrong to land, **stop and escalate** (stop-point 2). Merely large or out of
scope is not that.

### 6. Land

Commit in the worktree, then hand the merge to `worktree.sh land`:

1. In `$WT`: `git add -A && git commit` with a Conventional Commits message. The
   Decision(s) this change makes land in **this same commit** as the code.
   Pick the **commit type from what the change does**, not from what rode
   along. A change that alters the behaviour of `deploy/` or `scripts/` is
   never `docs:`, however much prose it also touched. The body carries a
   **`Cut:` line** naming what consolidate removed (pruned tests, dead code,
   deleted doc lines, a spent reference). Where there genuinely was nothing, it
   reads `Cut: nothing` with the reason. The nag flags a zero-deletion change,
   and this line is its answer. If the Plan declared a `Proof: real-environment`
   line, copy **that whole line verbatim** into the body, description and
   all. That trailer is how land's proof gate knows the test suite alone
   cannot prove this change. The text after the dash names the check the
   human must run. The gate prints it back to them, so never drop it.
2. From the primary tree, land the branch:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" land <change>
   ```

   It takes the land lock, so concurrent runs queue rather than interleave. It
   merges `--no-ff`, re-runs the whole suite in the primary tree, and on green
   removes the worktree and deletes the branch. Read its exit:

   - **0**: landed and green. Continue.
   - **9**: merge conflict. Aborted, tree restored. Fold in serially. Stop.
   - **6**: the merge regressed the trunk. Rolled back, worktree kept. Stop.
   - **7**: the proof gate wants real-environment proof. Run the check the
     refusal names, then record what you ran with `worktree.sh attest` and land
     again. Where you cannot run any real check, stop instead.
   - **8**: the authority gate wants a scoped grant for an irreversible change.
     Read the diff it printed, then record the authorization with
     `worktree.sh grant` and land again.
   - **5**: another session held the land lock past the timeout. Wait, retry.
   - **2**: usage or repo-state error (missing branch, detached HEAD): read
     the stderr message.

   Any non-zero exit: read `references/land.md` before acting on it. It carries
   what each code means and what resolves it. Three rules hold whatever the
   code. Never merge by hand. Never move the primary tree's HEAD to investigate
   (use a throwaway `git worktree add --detach` scratch tree). Never write a
   grant or a sign-off through the file tools or a shell redirect, because the
   `worktree.sh` helpers are what make the record readable.

Confirm to the user with the final report block from *Reporting*. It names
what landed, the Decisions/Notes written, what the change deleted (the Plan,
and any pruned tests), and what is next. Every cycle removes something.

## `--all`: many changes at once

Parallelism is `run` over several Plans, not a special mode, and it is never
assumed. **Check independence before spawning any worktree**. Each `plan-critic`
ran before the later Plans existed. So this is the first moment the whole set is
visible, and the cross-check is yours. Partition the set into disjoint Plans (run
in parallel) and overlapping ones (run sequentially, foundation first). State the
partition and its reason, then land one at a time. A change whose `add` exits 4 is
claimed by another run: skip it and say so.

Under `--all`, every progress line keeps its `[<change>]` prefix, so interleaved
steps stay readable. Also keep a status board: one line per Plan, reprinted
whenever any Plan changes state, and again as the run's final report:

```
csv-export   landed a1b2c3d
auth-retry   verify ...
rate-limit   queued (waits on auth-retry)
pdf-export   stopped at review: genuinely ambiguous, worktree kept
```

`references/parallel.md` carries the full comparison checklist, the claim rule,
and the landing order. Read it whenever the invocation is `--all`.

Where this session runs inside herdr (`HERDR_ENV=1`), `--all` spreads the Plans
over herdr tabs rather than running them here. This session becomes MAIN and
orchestrates. Each Plan gets a fresh Claude Code session in its own SUB tab,
which runs the same `/hone:run <change>` loop with the same gates. `--model`
picks the model for those sessions. `parallel.md` makes the check, and
`references/herdr.md` carries the topology and the exact commands.

## The three ways to stop

`run` proceeds without checking in. It stops only when:

1. **blocked with no resolution**: a gate won't go green and the fix is
   exhausted.
2. **genuinely ambiguous**: the Plan or the review leaves a real fork only the
   human can pick.
3. **done**: landed and green.

On 1 or 2, leave the worktree in place as evidence and escalate with the specific
blocker. Print a last progress line with the failing step marked `✗`, then end
with the final report block from *Reporting*. Never disable, weaken, or route
around a check to proceed. Stopping and reporting is a correct outcome. A forced
pass is not.

A constraint the Plan states is a check. Where the Plan orders this change after
another one, an unlanded predecessor is stop-point 1, not a fork for the human
to pick. Never edit a Plan to lift a constraint the Plan itself states, and
never offer that as a way forward.

The land gates are not a fourth way to stop. Both ask you for something the
suite cannot supply, and you supply it and land again:

- **Exit 8, the authority gate.** The change is irreversible. Read the signals
  and the diffstat the refusal printed. Decide whether the change is what the
  Plan asked for. Then record the authorization with
  `worktree.sh grant <change> "who/why"` and land again. The text you write
  lands in the merge commit body, so write the reason a reader would need a
  year from now, not "approved". If the diff does something the Plan never
  asked for, that is stop-point 2, not a grant to write.
- **Exit 7, the proof gate.** Run the check the refusal names. Where the change
  rewrites the proof harness, that is `bash scripts/proof.sh <change>` from the
  worktree. Elsewhere it is whatever the trailer declared, if you can reach it.
  Then record **what you actually ran and what it printed** with
  `worktree.sh attest <change> "<the check and its result>"`, and land again.

One rule holds both: **record only what you did**. A sign-off naming a check
nobody ran is worse than no gate, because it reads as evidence in git history
and carries none. Where the declared check is outside your reach (a browser
journey with no adapter, a canary you cannot watch), you have not proven it.
**Stop and escalate** with what you tried, and leave the sign-off to the human.
The stamp records that the agent signed, so a later audit can tell the two
apart.

Write both records through the helpers only. A file write or a shell redirect
into `.hone-grant/` or `.hone-proof/` skips the signer stamp, the commit
binding, and the placeholder check, and both guards deny it.
