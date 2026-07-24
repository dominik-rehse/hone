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
and `db/` but **not** the gate's own machinery. These rules stop `Write`/`Edit`
from mutating the test adapter or settings directly. Extend the list to any
other adapter or config your project treats as protected.

Then, once per project, install the test adapter and the durable-docs skeleton:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
```

`setup.sh` picks a test-adapter template for your ecosystem, gitignores the
ephemeral artifacts (`.worktrees/` and the markers — Plans are tracked), and creates
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
  artifact (what, why, how you'll know it works), and commit it — it is tracked,
  and the change's landing merge later removes it (git history keeps it).
- `/hone:run <change>`: execute that Plan through the loop and land it green.
  `/hone:run --all` runs every ready Plan, landed one at a time — after checking
  the set for independence: disjoint Plans run in parallel worktrees, overlapping
  ones sequentially.
- `/hone:garden`: the continuous-maintenance loop. Scans the whole repo for
  durable-layer drift between changes (orphan Notes, broken `Governs:` links,
  redundant tests, dead code, stale open questions) and lands the safe cuts —
  deletion-only, each proven safe by the suite — through the same worktree loop.
  Meant to run often and small, on whatever schedule the project already has (a
  print-mode `claude -p "/hone:garden"`).

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
  matching `src/` area, a Decision/Note whose `Governs:` path no longer exists, a
  merged `hone/*` branch land forgot to delete, or a change about to land that
  deletes nothing.

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
- `.hone-require-grant`: turn on the *authority gate*. Off by default — an
  undeployed project whose changes are all reversible never sees it. When
  present, `land` refuses a *consequential* change (destructive SQL, a `db/`
  deletion, or a `.hone-consequential-paths` match) until a scoped grant exists.
- `.hone-consequential-paths`: extend what counts as consequential beyond the
  built-in signals (one path glob per line, `#` comments). Only consulted when
  `.hone-require-grant` is present.
- `.hone-grant/<change>`: the scoped authorization for one consequential change.
  You create it (its text — who/when/why — lands in the merge commit body);
  delete it to revoke. Directory-ignored, per-developer.
- `.hone-proof-enforce`: turn on the *proof gate*. Off by default. When present,
  `land` refuses a change whose Plan declared `Proof: real-environment` unless it
  is discharged (`scripts/proof.sh` green, or a `.hone-proof/<change>`
  attestation).
- `.hone-proof/<change>`: your attestation that the real-environment check for one
  change ran (a browser journey, a canary). Discharges that change's proof
  obligation. Directory-ignored, per-developer.

## Tamper resistance

A `Bash` `PreToolUse` guard escalates or denies shell commands that would disable
the gate (`--no-verify`, `core.hooksPath`, creating `.hone-off`) or mutate a
protected artifact (the test adapter, a hook, settings). It closes only the
*shell* routes; the `Write`/`Edit` deny-rules in the *Install* block close the
file-tool routes. Together they deter and make tampering attributable; it is not
a sandbox.

## Authority (opt-in)

Tamper resistance is a *capability* boundary — what the agent may touch.
*Authority* is a separate contract — whether an unattended merge of a *consequential*,
effectively irreversible change (a destructive migration, a `db/` deletion) may
land without a human's say-so. A reversible change is `git revert`-able and lands
unattended as always; a dropped column is not. Turn the gate on with
`.hone-require-grant` (see *Off-switch and markers*): `land` then classifies the
diff and refuses a consequential change (exit 8, worktree kept as evidence) until
you record a scoped grant at `.hone-grant/<change>`, whose text lands in the merge
commit body. Left off, hone lands every green change unattended.

## Proof boundary (opt-in)

hone's checks prove *assertions* — the suite, types, lint, a fuzzed property, a
seeded mutant — all hermetic and pre-merge. A green check never proves a
real-environment outcome: a browser journey, a canary, deployed health. For a
change whose claim lives there, a Plan declares `Proof: real-environment`; with
`.hone-proof-enforce` on, `land` refuses it (exit 7, worktree kept) until it is
discharged by a real-environment adapter (`scripts/proof.sh`) or your attestation
(`.hone-proof/<change>`). Off by default, so undeployed work is never slowed.

## Adopting hone in an existing spec-driven repo

[`docs/converting.md`](docs/converting.md) is a migration prompt: run it inside a
repo built on a growing spec/acceptance-criteria corpus to distill the durable
residue into types, Decisions, and Notes, delete the rest, and adopt the plan→run
loop without changing runtime behaviour. Its final section is a shorter checklist
for upgrading a repo already on an earlier hone version to the current one.
