# hone

A Claude Code plugin that refines a codebase by cutting. A human writes a short Plan; an automated, worktree-native loop then
builds, verifies, consolidates, reviews, and lands each change unattended. Only
rot-proof durable truth survives in the repo, and every cycle deletes something.

*To hone is to sharpen a blade by grinding material away — refinement through
removal.*

The full model (artifacts, the loop, the checkers, the invariants) lives in
[`docs/model.md`](docs/model.md). This README covers install and use.

## Install

Add the plugin and enable it in your project's `.claude/settings.json`:

```json
{
  "enabledPlugins": { "hone@hone": true }
}
```

Then, once per project, install the test adapter and the durable-docs skeleton:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
```

`setup.sh` picks a test-adapter template for your ecosystem, gitignores the
ephemeral artifacts (`.plans/`, `.worktrees/`, the markers), and creates
`docs/decisions/`, `docs/notes/`, `docs/open-questions.md`, and `src/`. Add the
optional `scripts/typecheck.sh` and `scripts/lint.sh` where your language has
them; the gate runs each when present. The adapter contract is
[`templates/run-tests/README.md`](templates/run-tests/README.md).

hone assumes a `src/<area>/` layout: the guard requires a failing test before new
code under `src/`, the nag maps each Note to a `src/<area>/`, and the gate watches
`src/` and `tests/` for work in flight. Keep production code under `src/` (Python
packages too — `src/<pkg>/` is a supported layout), or that enforcement silently
does nothing.

## Use

- `/hone:plan <change>`: author `.plans/<change>.md`, the one hand-written
  artifact (what, why, how you'll know it works).
- `/hone:run <change>`: execute that Plan through the loop and land it green.
  `/hone:run --all` runs every ready Plan, landed one at a time — after checking
  the set for independence: disjoint Plans run in parallel worktrees, overlapping
  ones sequentially.

Everything after the Plan is automatic. `run` proceeds unattended and stops only
when blocked with no resolution, genuinely ambiguous, or done. On a stop it leaves
the worktree as evidence and escalates, and never disables a gate to proceed.

## Enforcement

Three hooks run the laws, from `hooks/`:

- *guard* (`PreToolUse`): no production code without a failing test, and no direct
  edits to `src/`, `tests/`, `docs/`, or `db/` in the primary tree (that work
  belongs in a worktree, landed by a merge). `.hone-durable-paths` extends the
  perimeter with project-specific paths.
- *gate* (`Stop`): the test suite, plus type-check and lint where present, stay
  green. A failure blocks the turn.
- *nag* (`Stop`, advisory): a leftover Plan, an oversized Note, a Note with no
  matching `src/` area, a merged `hone/*` branch land forgot to delete, or a
  change about to land that deletes nothing.

Two refute-first critics fill the judgment slots: `plan-critic` (admission, at
the end of `/hone:plan`, with the human present to revise a rejection) and
`consolidate-critic` (residue). Review reuses Claude Code's built-in `/code-review`.

## Off-switch and markers

All gitignored, per-developer, never checked in:

- `.hone-off`: disable every hook at once.
- `.hone-gate-enforce`: reserved for making advisory checks block (the gate blocks
  by default; this is for future advisory tiers).
- `.hone-nag-enforce`: make the nag's findings block instead of warn.
- `.hone-test-globs`: override the test-file basename globs (one per line) for a
  language whose tests don't match `*.test.* *.spec.* *_test.* *_spec.*`.
- `.hone-durable-paths`: extend the guard's durable perimeter beyond
  `src/ tests/ docs/ db/` (one entry per line, `#` comments): a directory
  (`deploy/`) or an exact file (`tsconfig.json`). Extends, never shrinks.

## Tamper resistance

A `Bash` `PreToolUse` guard escalates or denies shell commands that would disable
the gate (`--no-verify`, `core.hooksPath`, creating `.hone-off`) or mutate a
protected artifact (the test adapter, a hook, settings). Pair it with
`Write`/`Edit` deny-rules in `.claude/settings.json` for the file tools. This
deters and makes tampering attributable; it is not a sandbox.

## Adopting hone in an existing spec-driven repo

[`docs/converting.md`](docs/converting.md) is a migration prompt: run it inside a
repo built on a growing spec/acceptance-criteria corpus to distill the durable
residue into types, Decisions, and Notes, delete the rest, and adopt the plan→run
loop without changing runtime behaviour.
