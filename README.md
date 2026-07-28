# hone

A Claude Code plugin that refines a codebase by cutting. A human writes a short
Plan; an automated loop then builds, verifies, consolidates, reviews, and lands
each change unattended, working in an isolated git worktree. The repo keeps only
truth that cannot go stale, and every cycle deletes something.

*To hone is to sharpen a blade by grinding material away: refinement through
removal.*

The full model (artifacts, the loop, the checkers, the invariants) lives in
[`docs/model.md`](docs/model.md). This README covers install and use.

## Install

Add the plugin and enable it in your project's `.claude/settings.json`:

```json
{
  "enabledPlugins": { "hone@hone": true },
  "permissions": {
    "allow": ["Bash(claude -p:*)"],
    "deny": [
      "Write(./scripts/run-tests.sh)", "Edit(./scripts/run-tests.sh)",
      "Write(./scripts/typecheck.sh)", "Edit(./scripts/typecheck.sh)",
      "Write(./scripts/lint.sh)", "Edit(./scripts/lint.sh)",
      "Write(./.claude/settings.json)", "Edit(./.claude/settings.json)"
    ]
  }
}
```

The `permissions.allow` entry lets `run`'s review step invoke the native
`/code-review` in a nested headless Claude Code. Claude Code now disables model
invocation of that command, so hone runs it as a print-mode user turn
(`claude -p "/code-review …"`); without the rule that nested call is gated and
`run` can't stay unattended.

The `permissions.deny` entries are the file-tool half of hone's tamper
resistance (see *Tamper resistance* below). The `bash-guard` only closes the
*shell* routes around the gate; the `guard` protects `src/`, `tests/`, `docs/`,
`db/`, and `scripts/` in the primary tree, but not inside a worktree. These
rules stop `Write`/`Edit` from mutating the test adapter or settings anywhere.
Extend the list to any other adapter or config your project treats as
protected.

Then, once per project, install the test adapter and the durable-docs skeleton:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
```

`setup.sh` picks a test-adapter template for your ecosystem, gitignores the
per-developer artifacts (`.worktrees/`, `.hone-off`, and the grant/proof
sign-off directories; Plans are tracked), and creates
`docs/decisions/`, `docs/notes/`, `docs/open-questions.md`, and `src/`. Add the
optional `scripts/typecheck.sh` and `scripts/lint.sh` where your language has
them; the gate runs each when present. The adapter contract is
[`templates/run-tests/README.md`](templates/run-tests/README.md).

hone assumes a `src/<area>/` layout: the guard requires a failing test before new
code under `src/`, the nag maps each Note to a `src/<area>/`, and the gate watches
`src/` and `tests/` for work in flight. Keep production code under `src/` (Python
packages too: `src/<pkg>/` is a supported layout), or that enforcement silently
does nothing.

## Use

- `/hone:plan <change>`: author `.plans/<change>.md`, the one hand-written
  artifact (what, why, how you'll know it works), and commit it. It is tracked,
  and the change's landing merge later removes it (git history keeps it). Where
  prose would lose the detail, attach a *reference* under `.plans/<change>/` — a
  fixture, a sample payload, a mockup — and hand the loop the artifact instead of
  a description of it.
- `/hone:run <change>`: execute that Plan through the loop and land it green.
  `/hone:run --all` runs every ready Plan, landed one at a time. It first checks
  the set for independence: disjoint Plans run in parallel worktrees, overlapping
  ones sequentially.
- `/hone:garden`: the continuous-maintenance loop. Scans the whole repo for
  durable-layer drift between changes (orphan Notes, broken `Governs:` links,
  redundant tests, dead code, stale open questions, and drift in the project's own
  `CLAUDE.md` and skills) and lands the safe cuts (deletion-only, each proven safe
  by the suite) through the same worktree loop.
  Meant to run often and small, on whatever schedule the project already has (a
  print-mode `claude -p "/hone:garden"`).

Everything after the Plan is automatic. `run` proceeds unattended and stops only
when blocked with no resolution, genuinely ambiguous, or done. On a stop it leaves
the worktree as evidence and escalates, and never disables a gate to proceed.

## Enforcement

Three hooks run the laws, from `hooks/`:

- *guard* (`PreToolUse`): no production code without a failing test, and no direct
  edits to `src/`, `tests/`, `docs/`, `db/`, or `scripts/` in the primary tree
  (that work belongs in a worktree, landed by a merge). The committed
  `.hone-durable-paths` adds project-specific paths to the protected set.
- *gate* (`Stop`): the test suite, plus type-check and lint where present, stay
  green. A failure blocks the turn.
- *nag* (`Stop`, advisory): a leftover Plan, an oversized Note, a Note with no
  matching `src/` area, a Decision/Note whose `Governs:` path no longer exists, a
  merged `hone/*` branch land forgot to delete, a change about to land that
  deletes nothing, or a `type: project` entry in the harness's own memory store —
  that store sits outside the repo, so a decision left there is unreviewed,
  uncommitted, and invisible to the critics and to `garden`.

Two critics, each prompted to find fault rather than approve, fill the judgment
slots: `plan-critic` (checks the Plan at the end of `/hone:plan`, with the human
present to revise a rejection) and `consolidate-critic` (checks what a change
leaves behind in docs and tests). Review reuses Claude Code's built-in
`/code-review`.

## Configuration files

Two kinds, with different homes.

*Committed project policy* — shared by the team, reviewed like any other file:

- `.hone-durable-paths`: paths the guard protects beyond the built-in
  `src/ tests/ docs/ db/ scripts/` (one entry per line, `#` comments): a
  directory (`deploy/`) or an exact file (`tsconfig.json`). It only ever adds
  paths, never removes them.
- `.hone-irreversible-paths`: path globs that mark a change irreversible beyond
  the built-in signals (one glob per line, `#` comments). The pre-0.19 name
  `.hone-consequential-paths` still works.

*Per-developer, gitignored, never checked in:*

- `.hone-off`: disable every hook at once, for a quick manual edit outside the
  loop. Delete it when you're done.
- `.hone-grant/<change>`: your authorization for one irreversible change. Write
  who/when/why into the file; its text lands in the merge commit body. Delete
  it to revoke.
- `.hone-proof/<change>`: your sign-off that the real-environment check for one
  change ran (a browser journey, a canary). It must name the commit it proved
  (`echo "$(git rev-parse hone/<change>) — what you ran" > .hone-proof/<change>`),
  so it stops counting once you push more commits.

## Tamper resistance

A `Bash` `PreToolUse` guard escalates or denies shell commands that would disable
the gate (`--no-verify`, `core.hooksPath`, creating `.hone-off`) or mutate a
protected artifact (the test adapter, a hook, settings). It closes only the
*shell* routes; the `Write`/`Edit` deny-rules in the *Install* block close the
file-tool routes. Together they deter and make tampering attributable; it is not
a sandbox.

## Authority

Tamper resistance answers what the agent *can* touch. *Authority* is a separate
question: may an unattended merge land an *irreversible* change (a destructive
migration, a `db/` deletion) without a human's say-so? A reversible change can
be undone with `git revert` and lands unattended; a dropped column cannot be.
`land` classifies the diff and refuses an irreversible change (exit 8, worktree
kept as evidence) until you record a scoped grant at `.hone-grant/<change>`,
whose text lands in the merge commit body. In an undeployed project whose data
is disposable, the grant is the same one-line file; it just gets written more
readily.

## Proof boundary

All of hone's checks (the suite, types, lint, property tests, mutation checks)
run inside the repo, before the merge, needing nothing from the outside world.
A green check never proves a real-environment outcome: a browser journey, a
canary, deployed health. For a change whose claim lives there, a Plan declares
`Proof: real-environment`, and `land` refuses it (exit 7, worktree kept) until
a real-environment check passes (`scripts/proof.sh`, invoked as
`proof.sh <change>` from the change's worktree — see `templates/proof/`) or you
sign it off (`.hone-proof/<change>`, naming the commit it proved). The gate
only applies to changes that declare real-environment proof; everything else
lands on the suite as usual.

## Adopting hone in an existing spec-driven repo

[`docs/converting.md`](docs/converting.md) is a migration prompt: run it inside a
repo built on a growing spec/acceptance-criteria corpus to distill what is worth
keeping into types, Decisions, and Notes, delete the rest, and adopt the plan→run
loop without changing runtime behaviour. Its final section is a shorter checklist
for upgrading a repo already on an earlier hone version to the current one.
