# hone — a development model for AI-written codebases

*To hone is to sharpen a blade by grinding material away — refinement through
removal.* hone is a development model for codebases where an AI agent is a primary
writer *and* reader. It enforces the discipline of test-driven work but carries no
rot-prone corpus: there is no hand-maintained per-feature specification pile. It
refines the codebase by cutting: only rot-proof truth survives, and every cycle
removes something. Language-agnostic; examples use TypeScript and Python.

## The problem

Hand-maintained, per-feature behavioral specs serve two tenses at once: the
*temporary* work-ticket (what we're building now, its criteria, its checkboxes)
and the *permanent* description (how the system behaves today). Every batch of work
mints a new file and criteria are only ever added, so truth for one feature
scatters across many files and the pile grows without bound. Hand-maintained
behavioral prose always rots. It is a second copy of the system's behaviour that
nothing forces to stay in step with the code.

## Principles

1. *Discipline without a corpus.* Test-first is enforced; nothing maintains a
   permanent pile of per-feature specs.
2. *Durable truth lives only where it can't rot.* Everything else is disposable.
3. *The cut test.* Never write a durable line an agent could recover from the
   code, and if it can be a type, it is a type, not prose.
4. *Deletion is routine.* Every cycle removes something, counterbalancing a
   machine that otherwise only adds.
5. *The human plans; automation executes.* After the Plan, the loop runs
   unattended: hooks enforce the laws, critics fill the judgment slots, and it
   *escalates instead of forcing past a failed check*.
6. *All work happens in a worktree.* The primary tree is a merge target, never
   a workspace.

## Artifacts

At consolidate, each piece of durable residue is routed by a fixed test — cut
first, then type, then the smallest doc that fits:

```mermaid
flowchart TD
    r["Durable residue: what a change<br/>leaves behind that is worth keeping"] --> cut{"Could an agent recover<br/>it from the code?"}
    cut -->|"Yes, the code<br/>already carries it"| drop["Cut it.<br/>Write nothing"]
    cut -->|"No, nothing forces<br/>it to survive"| shape{"Can it be expressed<br/>as a type?"}
    shape -->|"Yes, it is a shape<br/>or a constraint"| type["Make it a type<br/>or a schema"]
    shape -->|"No, it is behavior<br/>or rationale"| kind{"What is it?"}
    kind -->|"A decision, and why<br/>it was made"| dec["Write it to<br/>decisions/"]
    kind -->|"An area's map and<br/>its one invariant"| note["Write it to<br/>notes/"]
    kind -->|"A bet only running<br/>code can settle"| oq["Log it in<br/>open-questions.md"]
```

*Durable — committed, survive the change:*

- *Types / schemas*: static types (TS; Python under mypy/pyright) and
  boundary/data schemas (Zod, Pydantic, JSON Schema, the DB schema). The
  strongest carrier: a checker fails when code and contract disagree, so they
  cannot drift.
- *Code*: `src/<area>/` (`thing.ts`, `thing.py`). The behavior itself.
- *Tests*: colocated by language convention (`thing.test.ts`,
  `test_thing.py`), behavior-named. Verify the *what* and document it.
- *Decision*: `docs/decisions/<topic>.md`. Present-tense: the current decision +
  why, plus a rejected-alternatives line when it's load-bearing (to stop a dead
  option being re-proposed). Edited freely when the decision changes; git carries
  the history and the commit message the why-it-changed. One per topic, landing
  in the same commit as the code it governs. May carry an optional `Governs:`
  line naming the `src/` paths it explains; the nag checks those paths still
  exist, so the prose is *mechanically* pinned to the code rather than left to
  rot silently (the one failure mode a checker can otherwise never see).
- *Note*: `docs/notes/<area>.md`. Per-area map + its one invariant, pointing
  at the Decision and the key types. Optional, 1:1 with an area, size-capped. Its
  key-type/Decision pointers can be a `Governs:` line, checked the same way.
- *Open question*: `docs/open-questions.md`. A bet only running code settles.
  Closed or deleted, never grown.
- *Git history*: what changed and why now.

*Ephemeral — tracked, but removed at consolidate:*

- *Plan*: `.plans/<change>.md`. The per-change brief: what, why, how I'll know
  it works. The only hand-written artifact; committed at `plan` (so the run's
  worktree inherits it off the trunk), then `git rm`'d at consolidate — the
  landing merge carries the deletion, git history keeps the Plan, the working
  tree does not.

*Enforcement — config, not docs:*

- *guard*: no production code without a failing test; no durable edits
  (`src/`, `tests/`, `docs/`, `db/`, plus `.hone-durable-paths` extensions) in
  the primary tree.
- *gate*: tests green, plus type-check and lint where the language has them
  (one adapter script keeps the hook language-agnostic).
- *nag*: leftover Plan, oversized Note, orphan Note, a Decision/Note with a
  broken `Governs:` link, a merged `hone/*` branch land forgot to delete, a
  change about to land that deletes nothing.

## The loop

*From your side*, two commands in, a landed change out, or a question handed
back to you:

```mermaid
flowchart LR
    you1(["1 · You sketch one change;<br/>/hone:plan turns the sketch<br/>into a Plan file with you"])
    you2(["2 · You hand the Plan<br/>to hone: /hone:run"])
    machine["3 · Hone works unattended, on an<br/>isolated copy of your repo:<br/>it builds test-first, runs every check,<br/>distills the docs, reviews the result"]
    landed["4 · The change lands on your<br/>main branch, tested, reviewed,<br/>documented. Until that merge,<br/>your repo was never touched"]
    back(["Or a question comes back<br/>to you: revise the Plan<br/>and re-run"])

    you1 --> you2 --> machine
    machine -->|"Everything green"| landed
    machine -.->|"Blocked, or a call<br/>only you can make"| back
    back -.-> you1

    classDef human fill:#fde68a,stroke:#b45309,color:#3f2d00;
    classDef machine fill:#ddd6fe,stroke:#6d28d9,color:#2e1065;
    classDef result fill:#99f6e4,stroke:#0f766e,color:#042f2e;
    class you1,you2,back human;
    class machine machine;
    class landed result;
```

*In full.* Nodes are colored by actor: *user command* (amber), *deterministic*
mechanical step (teal), *stochastic* model step (violet); the dashed
parallelogram is
the Plan, the one hand-written artifact. Work starts with a command: `/hone:plan`
takes your sketch and writes `.plans/<change>.md` with you; then `/hone:run`
launches everything downstream (`/hone:run --all` fans out over many Plans). Each
slash command is a discrete step; between them the loop runs itself. The Plan's
whole life is on the diagram: born at `/hone:plan`, deleted at consolidate.

```mermaid
flowchart TD
    cmdPlan(["First you type /hone:plan,<br/>giving it a sketch of the change"])
    planFile[/"Together you write the Plan.<br/>.plans/&lt;change&gt;.md:<br/>1 · what to build<br/>2 · why<br/>3 · how you'll know it works"/]
    cmdRun(["Then you type /hone:run.<br/>From here, hone works alone"])
    admit{"plan-critic asks:<br/>is the Plan clear, scoped,<br/>and free of collisions?<br/>(runs once, still inside /hone:plan)"}
    wt["A fresh worktree is spawned:<br/>an isolated copy of the repo<br/>where all the work happens"]
    build["Build: run a red-green cycle,<br/>once per behaviour<br/>(the cycle is shown below)"]
    verify["Verify: run every check<br/>(tests, types, lint,<br/>hygiene, mutation)"]
    cons["Consolidate, in this order:<br/>1 · save durable truth as docs or types<br/>2 · prune redundant tests<br/>3 · delete the Plan<br/>4 · consolidate-critic reviews (runs once)"]
    rev["Review: /code-review reads the<br/>whole change for bugs and cleanups<br/>(runs once; it is expensive)"]
    fix["Auto-fix: run the same red-green cycle,<br/>once per review finding<br/>(re-gated by verify, not re-reviewed)"]
    land["Land, in this order:<br/>1 · commit in the worktree<br/>2 · merge into main<br/>3 · re-run the full suite there<br/>4 · remove the worktree"]
    esc["Escalate: hand the<br/>problem back to you"]
    stop["Stop: halt where it is, keeping<br/>the worktree as evidence"]

    cmdPlan --> planFile
    planFile --> admit
    admit -->|"The Plan is sound:<br/>hand-off"| cmdRun
    admit -.->|"The Plan needs work:<br/>you revise it together<br/>and resubmit"| planFile
    cmdRun --> wt
    wt --> build
    build --> verify
    verify -->|"All checks pass"| cons
    verify -.->|"A check fails:<br/>fix and re-run until green"| build
    verify -.->|"Can't get it green"| stop
    cons --> rev
    cons -.->|"Deletes the Plan"| planFile
    rev -->|"Clean, nothing to fix"| land
    rev -.->|"Findings to fix"| fix
    fix --> land
    rev -.->|"Needs a decision<br/>only you can make"| stop
    land -.->|"Consequential or real-environment:<br/>awaits your grant or proof<br/>(opt-in gates)"| stop
    stop --> esc
    esc -.->|"You revise the Plan<br/>and re-run"| planFile

    classDef human fill:#fde68a,stroke:#b45309,color:#3f2d00;
    classDef deterministic fill:#99f6e4,stroke:#0f766e,color:#042f2e;
    classDef stochastic fill:#ddd6fe,stroke:#6d28d9,color:#2e1065;
    classDef artifact fill:#f1f5f9,stroke:#64748b,color:#1e293b,stroke-dasharray:5 3;
    class cmdPlan,cmdRun,esc,stop human;
    class wt,verify,land deterministic;
    class admit,build,cons,rev,fix stochastic;
    class planFile artifact;
```

Both `build` and `auto-fix` run the same red-green cycle, the loop's one
repeating unit. It is shown in full once:

```mermaid
flowchart TD
    ty["Types first:<br/>shape and constraints as types,<br/>illegal states made unrepresentable"]
    red["Red: write one failing test for<br/>an observable behaviour, then run it"]
    q1{"Does it fail for<br/>the right reason?"}
    disc["Discard and rewrite it:<br/>a test that passes now was<br/>written after the code"]
    green["Green: write the minimum<br/>code to pass it, then run it"]
    q2{"Passing now?"}
    refac["Refactor what you just wrote,<br/>then run the unit tier"]
    q3{"Still all green?"}
    more{"Another behaviour<br/>or finding to go?"}
    done(["Cycle done.<br/>Verify runs next"])

    ty --> red --> q1
    q1 -.->|"No, it passed or asserts nothing"| disc
    disc -.-> red
    q1 -->|"Yes, it fails correctly"| green
    green --> q2
    q2 -.->|"Not yet, write more"| green
    q2 -->|"Yes"| refac
    refac --> q3
    q3 -.->|"No, a check went red"| green
    q3 -->|"Yes"| more
    more -->|"Yes"| red
    more -->|"No"| done

    classDef stochastic fill:#ddd6fe,stroke:#6d28d9,color:#2e1065;
    classDef deterministic fill:#99f6e4,stroke:#0f766e,color:#042f2e;
    class ty,red,green,refac,disc stochastic;
    class done deterministic;
```

- *plan* (`/hone:plan`): author `.plans/<change>.md`. The only manual step. Size
  a change to the smallest unit worth its own review gate: split only where a
  reviewer could reject one part while approving its neighbor. It ends with
  *admission*: `plan-critic` checks placeholders, contradictions, ambiguity,
  scope, and collision with an open change, and a rejection is revised with the
  human on the spot — the one moment they are guaranteed present — so no flawed
  Plan is handed off.
- *run* (`/hone:run`): per Plan, in a fresh worktree:
  - *build*: red-green: type, failing test, then code; `guard` enforces the
    order.
  - *verify*: `gate` and `nag`, plus a mutation check on critical paths.
  - *consolidate*: route durable residue (a type, a Decision, a Note, a closed
    question), prune redundant tests, delete the Plan; `consolidate-critic`
    reviews.
  - *review*: Claude Code's built-in `/code-review` on the finished change.
  - *land*: commit, merge into the primary tree, re-run the whole suite there,
    remove the worktree.

Every step's completion is confirmed by its artifacts (the diff, the gate
output), never by a subagent's report that it finished. A failed check is not a
stop, and only the `build`⇄`verify` cycle loops: a red gate or a surviving mutant
sends the agent back to `build` for another red-green cycle, as many times as it
takes to go green. The model checks each change *once* per slot: `plan-critic`
(at `/hone:plan`), `consolidate-critic`, and the expensive `/code-review`; their findings are
applied or auto-fixed in place, and a review fix is a red-green cycle re-gated by
`verify`, never a second review. A confirmed finding may be declined only when
it contradicts the Plan's explicit stance or falls outside the change, and the
decline is recorded durably (the landing commit's body, or an open question for
a deferred defect), never left in the conversation alone. The agent self-corrects in the worktree and
escalates only at the two stop-points on the diagram: verify can't go green once
the fix is exhausted, or review finds the change genuinely ambiguous. (A flawed
Plan never reaches `run`: admission rejects it inside `/hone:plan`, where the
human is present to revise it.) On a stop it leaves the worktree in place as evidence; the
human revises the Plan and re-runs (or abandons the change), never disabling a
gate to proceed. The Plan is the sole re-entry point: the human does not hand-fix
code mid-loop.

*A bug fix is the same loop:* `build` opens with a failing test that reproduces
the defect, then fixes the root cause, never a fix confirmed by a test written
after. *Exploration is not:* a spike runs in a throwaway worktree that is
discarded, never landed; its finding becomes a Decision or a Note, not committed
code.

## Checking

Two kinds of checker; choosing the wrong kind is the main failure.

```mermaid
flowchart TD
    q{"Is the question<br/>computable?"}
    q -->|"Yes, a deterministic<br/>answer exists"| mech["Mechanical check: a hook or<br/>a mutation run. Always runs,<br/>and cannot be fooled"]
    q -->|"No, it takes<br/>a judgment call"| judge["Judgment check: a critic subagent<br/>with a constructed brief, prompted<br/>to refute. Runs once"]

    classDef deterministic fill:#99f6e4,stroke:#0f766e,color:#042f2e;
    classDef stochastic fill:#ddd6fe,stroke:#6d28d9,color:#2e1065;
    class mech deterministic;
    class judge stochastic;
```

*Mechanical.* Deterministic, no model calls, unfoolable, always run: the hooks
above plus mutation testing. Prefer mechanical wherever the question is
computable.

*Judgment.* Subagents, only where no hook can answer. Each gets a *constructed*
brief (the diff, the Plan, the relevant Decisions and Notes), never the writer's
transcript; inheriting the writer's context is not independent review. It is
prompted to *refute and argue for deletion* rather than approve, and runs *once*,
returning structured findings.

- `plan-critic`: placeholders, contradictions, ambiguity, scope; belongs in an
  existing area? Runs inside `/hone:plan`, so a rejection is revised with the
  human present rather than escalated mid-run.
- `consolidate-critic`: Decision restating code? Note drifting into a spec?
  redundant test? abstraction earning its keep?
- `/code-review`: Claude Code's built-in workflow-backed command for correctness
  plus what to delete; already multi-agent (parallel finders + a verification
  pass), so the loop reuses it rather than shipping its own reviewer. Model
  invocation of the command is now disabled, so the loop runs it as an explicit
  user invocation in a nested headless Claude Code (a print-mode `/code-review`)
  reading the worktree diff; it must not fall through to a marketplace
  `code-review` plugin, which is GitHub-PR-shaped.

These critics are the only judgment inside the loop; together with the
mechanical checks they are the whole trust foundation. The human's judgment
sits before (the Plan) and after (auditing the merged result).

The critic prompts and the injected `rules/workflow.md` are themselves
behavior-shaping prose doing real judgment work. Check them against evals (a
suite of past changes with known-good verdicts) rather than assuming they hold;
unverified prose is the one part of the trust foundation that can rot silently.

### The proof boundary (land-time, opt-in)

hone's checks prove *assertions*: the suite, types, lint, a fuzzed property, a
seeded mutant — all hermetic, pre-merge, in-repo. That is the boundary. A green
check proves only its assertion, never a real-environment outcome: a browser
journey, a canary, deployed health, behaviour a user actually observes. For a
change whose claim lives at that altitude, "landed, tested, reviewed" is not
"proven", and pretending otherwise is the trap.

So the boundary is named, not hidden. A Plan whose proof is user- or ops-level
declares `Proof: real-environment` (the `plan-critic` rejects a Plan whose proof
is *categorically* incapable of settling its claim). With the proof gate on
(`.hone-proof-enforce`, off by default so undeployed work is never slowed), such a
change may not land on the assertion suite alone: it is discharged by a
real-environment adapter (`scripts/proof.sh`, which checks the deployed system,
not the tree) or a human attestation (`.hone-proof/<change>`), and otherwise land
refuses (exit 7) and the run escalates — a land-time escalation the loop diagram
shows alongside the authority gate, faithful to *escalate, never force*: proof the
loop cannot give is handed back, not faked.

### Property-based tests (build-time)

A property states a rule once (`parse(serialize(x)) == x`) and a fuzzer
hammers it, so the writer cannot game inputs it does not pick. *Use* for
modules with a universal invariant: parsers, serializers, pure transforms,
especially on critical paths. *Skip* where no universal rule exists: UI,
orchestration, glue. Complements, never replaces, example tests that pin
specific behavior.

### Mutation tests (verify-time)

Seed small bugs and check a test catches them: the unfoolable judge of hollow
tests, which matters because the same agent wrote the code and the tests. *Use*
diff-scoped and budget-capped, on critical paths only. *Skip* whole-suite runs
(cost, noise) and UI behavior; it audits the tests, not the code, and never
gates a trivial change. Runner maturity varies by ecosystem (StrykerJS for
JS/TS; mutmut or cosmic-ray for Python), so check before relying on it.

Both are *verification independent of the author*: the writer can game its own
examples and its own self-review, but not a fuzzed property or a seeded mutant.

## Authority

Capability and authority are separate contracts. The `guard` and `bash-guard`
answer *can the agent act* — where it may write, which shell routes stay open.
Authority answers a question deliberately *not* delegated to the model: *may an
unattended merge land this consequential act at all.* The axis is reversibility.
A reversible change — a logic bug, a wrong refactor — is `git revert`-able, so its
cost is bounded and it lands unattended, as the vast majority do. An *irreversible*
one — a dropped column, a destructive backfill, a truncate — is not undone by
reverting the merge; the data is already gone. For that subset, green-and-reviewed
is necessary but not sufficient.

The authority gate is opt-in (`.hone-require-grant`), off by default so an
undeployed project with disposable data is never slowed. When on, `land`
classifies the diff mechanically — destructive SQL in a migration or `db/` file, a
`db/` deletion, any `.hone-consequential-paths` glob — and a consequential change
may not merge without a *scoped grant* the human writes at `.hone-grant/<change>`:
scoped (one change), revocable (delete the file), auditable (its text lands in the
merge commit body), recoverable (the worktree stays as evidence until it is
granted). No grant → `land` refuses before the merge (exit 8) and the run escalates.
It extends `bash-guard`'s escalate-on-consequential-shell-op instinct to the one
consequential act the loop performs itself: the merge.

## Types and abstractions

Anything expressible as a type belongs in a type, not prose: an interface, a
constraint, an illegal state made unrepresentable (a discriminated union in TS,
a `Literal` in Python). Types carry *shape and constraint*; behavior stays in
tests, *why* in Decisions.

Their failure mode is over-abstraction, not rot, and no checker flags it: a
type checker verifies a type is correct, never that it is wise. (Where checking
is opt-in, as with mypy or pyright, adopting it is a deliberate choice; the
discipline matters more, not less.) So abstractions are judged *reactively, at
the point of change*, never by proactive hunt, since hunting breeds premature
abstraction:

- At *build*, friction is the signal. Rule of three: duplicate until the
  abstraction proves itself.
- At *consolidate*, `consolidate-critic` asks whether the change *revealed* a
  wrong abstraction (a generic with one caller; two types that should merge).
  This named slot is essential: nothing else forces the look.
- What is not being changed is not managed. A bad abstraction costs only at
  change-time. Exception: *recurring* friction on a foundational type across
  several changes triggers a deliberate, Decision-level reconsideration.

## Many changes at once

Parallelism is `run` over several Plans, each in its own worktree, landed one
at a time, not a special mode. Three rules:

- *Within a change the loop is serial.* Each red-green cycle learns from the
  last; the unit of parallelism is the change, never the cycles inside it.
- *Independence is checked before fan-out, never assumed.* Each `plan-critic`
  ran at plan time, before later Plans existed, so `run` compares the complete
  set first — expected files and areas, shared types and persistent contracts,
  Decisions and Notes more than one Plan would touch — and partitions:
  disjoint Plans fan out in parallel; overlapping Plans run sequentially, each
  landing before the next starts, so the later change builds on the landed
  result.
- *Independence is verified at the merge.* A merge collision on a shared type
  or Note means the upfront check missed a seam: that seam becomes one serial
  change and a Decision-level reconsideration. After all merges, a *global
  consolidate pass* catches cross-change duplication no single worktree could
  see.

`/hone:run --all` fans a worktree agent out per independent Plan, sequences the
overlapping ones, and lands them all through the same conservative
merge-and-verify stage.

## Continuous maintenance

`plan → run` cuts a change's residue at the point of change. But rot also
accumulates *between* changes, across the parts nothing is currently touching: a
Decision whose code moved, a Note nobody re-derived, a test a later change made
redundant, an open question running code already settled. *What is not being
changed is not managed* holds for abstractions (judged reactively); it leaves a
gap for the durable layer as a whole, which no diff-scoped hook can see.

`garden` (`/hone:garden`) is the standing loop that closes it: it scans the whole
repo for that drift and lands the safe cuts through the *same* worktree loop, one
at a time. Two properties keep it honest. It is **deletion-only** — a garden
change removes and never adds, so it can only shrink the surface, extending
principle 4 (*every cycle removes something*) from a per-change habit to a
scheduled one. And it is **self-verifying**: the gate's suite is the proof a cut
is safe — a deletion that stays green was dead, one that reddens was load-bearing
and is abandoned. The judgment calls (is this Decision stale, or load-bearing
rationale?) go to the `consolidate-critic`, repo-wide; durable rationale is never
cut by machine on a hunch, and anything only a human can settle is logged or
escalated, not guessed. Run it often and small — a trickle of cuts, not a periodic
reckoning. hone owns the loop, not the timer: the schedule is the project's
existing cron/CI invoking a print-mode `/hone:garden`.

## Filetree

```
hone/                            # the plugin — the machinery (installs once)
├── .claude-plugin/plugin.json
├── rules/workflow.md            # lean always-on trigger, injected at session start
├── skills/{plan,run,garden}/SKILL.md   # /hone:plan, /hone:run, /hone:garden
├── hooks/                       # the laws
│   ├── {guard,gate,nag}.sh + hooks.json
│   ├── bash-guard.sh            # tamper resistance for the gate
│   └── session-start.sh         # injects rules/workflow.md; nudges setup
├── scripts/{worktree,setup}.sh  # worktree add/land/remove; one-time project setup
├── agents/{plan-critic,consolidate-critic}.md   # the judgment (review reuses /code-review)
├── templates/run-tests/         # the one test-adapter contract, per ecosystem
└── evals/                       # known-good verdicts for the critics and the rule

repo/  (primary tree — a merge target, never worked in)
├── src/<area>/                  # code + tests: thing.ts/thing.test.ts,
│                                #               thing.py/test_thing.py, ...
├── docs/{decisions/, notes/, open-questions.md}
├── scripts/run-tests.sh         # the test adapter (installed by setup.sh)
├── .plans/<change>.md           # tracked — hand-written; git-rm'd at consolidate
├── .worktrees/<change>/         # gitignored — one per in-flight change
└── .claude/settings.json        # enables the plugin; deny-rules protect gates
```

`rules/workflow.md` is a *pointer, not the manual*: a paragraph naming the
plan→run workflow and its invariants, so the always-on context stays cheap and
gets obeyed (a long always-on rule burns the budget every session and is ignored
once it grows). The operational detail lives in the `plan` and `run` skills,
loaded only when invoked (progressive disclosure). For a single repo rather than
a distributed plugin, that trigger is just as well a lean `CLAUDE.md` pointing at
local skills; the detail-in-skills split is the same either way.


## What writes what

W = writes · M = amends · P = prunes/deletes · R = reads · — = untouched

| Operation   | .plans/ | code | tests | decisions/ | notes/ | open-q | .git |
|-------------|---------|------|-------|------------|--------|--------|------|
| plan        | W       | —    | —     | —          | —      | (W)    | W    |
| build       | R       | W    | W     | —          | —      | —      | —    |
| verify      | —       | R    | R     | R          | R      | R      | —    |
| consolidate | P       | —    | P     | W/M        | W/M    | M      | —    |
| land        | —       | —    | —     | —          | —      | —      | W    |
| garden      | P       | P    | P     | P          | P      | P      | W    |

(W) on open-q: only when the Plan surfaces a new open question. plan's `.git` W
is the Plan commit on the trunk (so the run's worktree inherits it); consolidate's
`.plans/` P is a `git rm` staged in the worktree that land's commit and merge
carry back to the primary tree. *garden* is not part of the plan→run change; it is
the standalone maintenance loop, deletion-only (every column it touches is a prune)
and landing its cuts through the same merge (`.git` W). It never writes durable
prose — a stale doc it can only cut, never edit.

## Invariants

1. Code and tests are written only by *build*, and durable artifacts are pruned
   only by *consolidate* — or, between changes, by the standalone *garden* pass,
   its deletion-only counterpart (never by *build*, *verify*, or *land*). `docs/`
   prose is written only by *consolidate*; `.plans/` deleted only by
   *consolidate*. Work-in-progress cannot leak into durable truth: the structural
   cure for the spec pile.
2. A Note is optional, 1:1 with an existing area, and size-capped, held by the
   correspondence and size checks; the *carving* of areas is judged by
   `/code-review`.
3. Every `docs/` write passes the cut test (principle 3).
4. The primary tree's durable artifacts are written only by *land*, a merge;
   `guard` blocks direct source edits there, so no half-built change ever sits
   in the tree everything merges into. The one hand-authored exception is the
   Plan (`.plans/`, outside `guard`'s perimeter), committed there at *plan* so
   the run's worktree inherits it and land's merge can remove it.
