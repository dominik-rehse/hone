# Code-quality checks through the lint and type-check adapters

hone ships no analyzer. It runs two optional adapters of the project,
`scripts/lint.sh` and `scripts/typecheck.sh`, in the gate and again after
the merge at land. Any check that a program can decide belongs in one of
them. Then every change meets the check, and no prompt has to ask for it.

This page maps hone's goals for a codebase to the kinds of tool that check
them. The tool names are leads from a search on 2026-09-18, and hone depends
on none of them. Read the documentation of a tool before you adopt it.

## Contract

- hone runs each adapter with no argument, from the root of the tree under
  check. That tree is the worktree in the gate, and the primary tree at land.
- Exit `0` means green. Any other exit blocks the stop or rolls the merge
  back, and hone shows the end of the output to the agent.
- An adapter that runs several tools runs all of them and then fails. The
  agent then sees every finding in one pass:

```bash
#!/bin/bash
rc=0
npx eslint src || rc=1
npx jscpd src --min-tokens 70 --exit-code 1 || rc=1
exit "$rc"
```

- The gate runs the adapters on every stop with a dirty tree, so keep them
  fast. Put a slow whole-project analysis behind a check on the changed
  files, where the tool has one.

## Which check serves which goal

- *No duplicated logic.* A clone detector. jscpd reads most languages and
  has `--min-tokens`, `--threshold`, and `--exit-code`. PMD CPD lists every
  copy of a clone in one entry and needs a JVM. hone's own rule is the rule
  of three, so set the size threshold high enough that two small copies
  pass.
- *No dead code.* knip for JavaScript and TypeScript, vulture for Python,
  the `deadcode` command for Go, cargo-shear or cargo-machete for Rust.
  Go's `deadcode` exits 0 on a finding, so the adapter must fail on output.
- *Small functions.* The linter of the language has the rules. ESLint,
  oxlint, and Biome have `complexity` and `max-lines-per-function`. ruff has
  `C901` and `PLR0915`. lizard reads about 27 languages and takes thresholds.
- *Boundaries between areas, and no import cycle.* dependency-cruiser for
  JavaScript and TypeScript, with `--affected <revision>` for the changed
  modules. import-linter or tach for Python.
- *Types carry what types can carry.* The strict mode of the compiler goes
  into `scripts/typecheck.sh`: `tsc --noEmit` with `strict`, basedpyright,
  or pyrefly. The `strictTypeChecked` preset of typescript-eslint and
  type-coverage go into `scripts/lint.sh`.
- *Links in the docs resolve.* hone's nag checks relative links in Notes and
  Decisions. lychee checks the rest, and it has an offline mode.

## What no tool decides

No program decides these four, so they stay with the `consolidate-critic`:

- a sentence in a document that a change made false
- an abstraction with one user
- a string that should be a closed set of values
- a test that repeats another test

hone narrows the first one mechanically. `worktree.sh governed <change>`
lists the Notes and Decisions about the code that a change touched, and the
loop hands them to the critic.

hone's nag checks one more goal without any tool. It names a `src/<area>/`
that a change touched and that holds more lines than `HONE_AREA_MAX_LINES`.
