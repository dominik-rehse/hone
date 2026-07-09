# Converting a stdd repository to hone

This is a migration prompt. It is the one place in hone that names *stdd*, the
spec-and-test methodology hone descends from, because it operates on a repository
still laid out that way. Run it **inside the target repo** (for example one with
60+ specs and 500+ acceptance criteria), with this plugin's
[`docs/model.md`](model.md) readable. Use subagents for the bulk per-spec
distillation; each spec is independent.

---

> Convert this repository from the stdd methodology to hone. Read
> `<hone>/docs/model.md` first. Goal: replace stdd's growing spec/AC corpus with
> hone's durable layer (types, present-tense Decisions, small Notes, legible
> tests) and adopt its plan→run worktree loop, **without changing runtime
> behavior**: the test suite stays green at every step. Work on a branch, in
> stages, committing after each.
>
> 1. **Inventory.** List `docs/specs/*`, `docs/decisions/*`,
>    `docs/open-questions.md`, the overview docs (architecture, entities, ui,
>    out-of-scope), and the stdd machinery (`.stdd-*` markers, its hooks,
>    `scripts/run-tests.sh`, the precommit gate).
>
> 2. **Distill specs, then delete them.** Classify each `docs/specs/*.md`:
>    (a) a work-batch or fix spec (names like `*-review-fixes`, `*-pass`,
>    `*-audit-fixes`) — its behavior already lives in code and tests; delete it
>    outright. (b) a feature spec — extract only durable truth the code cannot
>    show: an intent or invariant → a **Note** (`docs/notes/<area>.md`, ≤ ~half a
>    screen, one per `src/` area); a decision + why → a **Decision** (step 3); a
>    shape or constraint expressible as a **type** → make it a type in `src/`.
>    Then delete the spec. Do not preserve acceptance criteria, checkboxes, or
>    per-criterion prose. Git keeps the history. Never delete a spec before its
>    residue is captured; if the residue is ambiguous, leave the spec and flag it
>    for a human.
>
> 3. **Convert ADRs to Decisions.** `docs/decisions/adr-NNN-*.md` are append-only
>    with superseded chains. Collapse each topic into one present-tense
>    `docs/decisions/<topic>.md`: the current decision + why, plus a
>    rejected-alternatives line where a superseded record explains why an option
>    was dropped. Drop the `adr-NNN` numbering; git holds the history.
>
> 4. **Overview docs → Notes or delete.** architecture / entities / ui become
>    short per-area Notes (a map + one invariant, pointing at Decisions and key
>    types), or are deleted where they only restate code. out-of-scope items fold
>    into the relevant Decision's rejected-alternatives line.
>
> 5. **Open questions.** Keep the file; close or delete resolved and stale
>    entries.
>
> 6. **Tests.** Split oversized test files by `src/` area; rename tests to
>    describe behavior, not `slice-N`/`AC-N`; strip the archaeology tags. Keep the
>    suite green at every step. (Deduplicating tests via mutation testing is a
>    later hone cycle, not part of conversion.)
>
> 7. **Swap the machinery.** Remove the stdd markers, hooks, and scripts
>    (`.stdd-*`, the precommit gate, the guard/audit wiring) and install the hone
>    plugin (guard/gate/nag hooks, plan/run skills). Keep or rename the test
>    adapter to hone's `gate` contract. Add a gitignored `.plans/` and adopt the
>    worktree-native flow.
>
> 8. **Verify.** Full suite green; type-check clean; `grep -rn 'stdd\|AC-\|slice-'`
>    and reconcile every leftover; confirm no `docs/specs/` remains.
