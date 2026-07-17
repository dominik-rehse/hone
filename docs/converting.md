# Converting a stdd repository to hone

This is a migration prompt. It is the one place in hone that names *stdd*, the
spec-and-test methodology hone descends from, because it operates on a repository
still laid out that way. Run it **inside the target repo** (for example one with
60+ specs and 500+ acceptance criteria), with this plugin's
[`docs/model.md`](model.md) readable. Use subagents for the bulk per-spec
distillation; each spec is independent.

One manual prerequisite: install and enable the hone plugin in Claude Code
(`/plugin marketplace add dominik-rehse/hone`, then install `hone@hone`) before
running this. Everything else is automated in the steps below, including the
enforcement sequencing — the migration is a one-time rewrite of the primary tree,
so it runs with *both* enforcement layers off (neither methodology's loop applies
to a bulk rewrite). Step 0 silences stdd and keeps hone dormant with a `.hone-off`
marker; step 9 flips hone on once the suite is green. Enabling the plugin early is
therefore harmless: it stays inert until step 9.

---

> Convert this repository from the stdd methodology to hone. Read
> `<hone>/docs/model.md` first. Goal: replace stdd's growing spec/AC corpus with
> hone's durable layer (types, present-tense Decisions, small Notes, legible
> tests) and adopt its plan→run worktree loop, **without changing runtime
> behavior**: the test suite stays green at every step. Work on a branch, in
> stages, committing after each.
>
> 0. **Silence enforcement, then branch.** Create a branch for the migration.
>    Then `touch .stdd-off` and `touch .hone-off`. stdd's audit and guard would
>    fight the spec deletions and tag stripping below; hone's guard forbids
>    editing `src/`, `tests/`, or `docs/` in the primary tree — which is exactly
>    what this bulk rewrite does, since it is not a `plan → run` worktree cycle.
>    Both markers are gitignored, so the migration runs unenforced, like a spike,
>    and you keep the suite green by hand.
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
>    (all `.stdd-*` — including the `.stdd-off` from step 0 — the precommit gate,
>    and the guard/audit wiring). The hone plugin is already installed (the
>    prerequisite above); keep or rename the test adapter to hone's `gate`
>    contract, and `mkdir -p src` plus create the gitignored `.plans/`. Leave
>    `.hone-off` in place for now — step 9 removes it.
>
> 8. **Verify.** Full suite green; type-check clean; `grep -rn 'stdd\|AC-\|slice-'`
>    and reconcile every leftover; confirm no `docs/specs/` remains.
>
> 9. **Turn hone on.** With the suite green and every leftover reconciled, remove
>    `.hone-off` so the guard, gate, and nag activate. Smoke-check that they fire:
>    an edit to a `src/` file is now denied in the primary tree, and a Stop runs
>    the gate. Commit, merge the branch, and from here every change goes through
>    `/hone:plan` → `/hone:run` in a worktree.

---

## Notes from live conversions

None of this changes the nine steps; it just makes them go smoother.

- **Fan out with disjoint ownership.** Run the docs distillation (steps 2/4/5)
  and the test de-tagging (step 6) as _parallel_ subagents — they touch `docs/`
  and `src/`+`tests/` respectively, so they never collide. Split the ADR
  conversion (step 3) across subagents by disjoint output files, but hand every
  one the _same_ number→slug map so cross-references stay consistent. Have the
  distiller own `docs/` only and _report_ any needed `src/` type rather than
  adding it, so it can't race the de-tagger. Keep Notes sparse — one per `src/`
  area at most, only for an invariant the code and Decisions can't show (a whole
  large codebase may need just two or three).

- **Renaming ADRs has a blast radius far beyond `docs/decisions/`.** Numbered-ADR
  references live in rules, the README, the manual, runbooks, deploy configs
  (systemd units, nftables, compose files, Caddyfile, yaml), DB DDL, scripts, and
  code comments. After step 3, sweep every `ADR-NNN` / `decisions/NNN-*.md`
  reference — including compact `ADR-004/014` forms — to the new slugs with a
  scripted number→slug map, then `grep -rn 'ADR-[0-9]\{3\}\|decisions/[0-9]\{3\}-'`
  to confirm none remain. A repo whose Decisions are _already_ topic-named skips
  this entirely: only a light present-tense cleanup of each file is needed (drop
  the `ADR:`/`Status:` framing and any `Applies to: every spec` boilerplate).

- **The gate-critical files fight the Edit tool.** stdd's tamper-resistance adds
  `Edit()`/`Write()` deny rules for `.claude/settings.json`, `lefthook.yml`, and
  `scripts/run-tests.sh` — so in step 7 edit those with a shell command
  (sed / python / cp), not Write/Edit, and trim the deny list itself to hone's
  shorter form as you go. Adopt hone's `scripts/run-tests.sh` by copying it (the
  stdd adapter still self-labels "stdd" in its comments). `.hone-durable-paths` is
  a local, gitignored per-developer file; `.claude/rules/hone-guard.md` is
  committed. Leave any unrelated git hooks (e.g. a semantic-index tool's) alone.

- **Preserve a widely-cited spine as a Note.** If an overview doc carries a list
  everything references — a HARD RULES security spine, a domain model — don't just
  delete it. Land it as a Note (e.g. `notes/security-model.md`) so the many
  `HARD RULE N` / `architecture.md §…` references elsewhere still resolve, and fix
  those references to point at the Note.

- **Verify twice.** Step 8's `grep` for `stdd|AC-|slice-` catches the tags; also
  grep for links to the docs you deleted (overview docs, specs) and check the
  non-`.md` deploy configs a text sweep tends to skip. A repo-local `.env` /
  `.env.example` may be permission-blocked from tooling — note any leftover
  reference there for a human rather than forcing it.
