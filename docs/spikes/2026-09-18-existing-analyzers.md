# Spike: which existing analyzers can enforce hone's goals for a codebase?

**Date:** 2026-09-18 · **Status:** frozen. Written once, never maintained
against the code.

## Question

hone wants deterministic checks for its goals wherever one is cheap
(`docs/roadmap.md`, rule 5). Which checks exist already as software that a
project can run from a script, and which does nobody offer?

## What I did

Ran four web searches in parallel, one per topic, each by a research agent.
The topics were copied code, dead code with size and complexity, structure
with type strictness, and stale documents with commit messages and test
quality. Each agent checked its claims against the tool's own repository or
documentation where it could, and it named what it could not check. One
agent ran jscpd 5.2.1 and pylint on three identical files. No other tool
was installed or run. I did not check the agents' reports myself, so treat
every version, date, and license below as a lead to check.

## Finding

### A maintained tool exists, per language

- *Copied code.* jscpd 5 (MIT, about 220 formats) is the polyglot default.
  Its JSON is pairwise, so three copies come out as two pairs, and a script
  must group them to count a third copy. PMD CPD lists N files per clone
  natively and needs a JVM. qlty exits 0 when it finds a smell, and its
  license forbids use in an AI coding service. dupehound is the only tool
  with a real diff mode, and it was three months old.
- *Dead code.* knip for JavaScript and TypeScript, vulture for Python, the
  official `deadcode` for Go, cargo-shear or cargo-machete for Rust. Go's
  tool exits 0 on findings, so it needs a wrapper. ts-prune, unimported,
  and depcheck are dead.
- *Function size and complexity.* lizard covers about 27 languages with
  thresholds and an exit code. Inside one language the linter has the
  rules already: ESLint, oxlint, Biome, ruff.
- *Module boundaries and cycles.* dependency-cruiser for JavaScript and
  TypeScript, with `--affected <rev>` for changed modules. import-linter or
  tach for Python. ArchUnit, deptrac, and go-arch-lint elsewhere. No
  mature polyglot tool exists.
- *Type strictness.* `tsc` with `strict`, the `strictTypeChecked` preset of
  typescript-eslint, and `type-coverage --at-least N`. For Python,
  basedpyright with a baseline file, or `pyrefly coverage check
  --fail-under N`.
- *Links in documents.* lychee, one binary, with an offline mode.
- *Commit messages.* commitlint is the only tool with a rule that requires
  a custom trailer, and it needs Node 22. A grep over
  `git log --format=%B <base>..HEAD` does the same.
- *Mutation tests on a diff.* cargo-mutants and PIT have a diff mode.
  StrykerJS and mutmut have an incremental cache and no diff flag.

### No bundle covers it all

SonarQube needs a server. MegaLinter and Super-Linter need Docker. qlty has
the limits above and no dead-code engine. fallow (JavaScript and TypeScript
only) and aislop (a wrapper around several linters, with rules for what a
coding agent leaves behind) aim at hone's case. Both were young, with no
independent record.

### What nobody has built

- *A check that a sentence in a document is false.* Tools do the step
  before it. Fiberplane Drift binds a document to a code symbol, stores a
  fingerprint of the code, and exits 1 when the code changed. A person or a
  model then reads the document again. That is hone's `Governs:` line plus
  a fingerprint. cog and embedme remove the repeat instead: the value lives
  in code, and the document pulls it in.
- *A size cap per directory.* Counters such as scc and tokei report sizes
  as JSON, and none has a gate. One paper (arXiv 2605.14362) reports that
  bytes and tokens correlate at 0.997, so a line cap is a fair proxy for
  "fits in context".
- *An abstraction with one user*, outside Go's `iface` analyzer, which is
  off by default for its false alarms.
- *A string that should be a union.* typescript-eslint closed the proposal
  as wontfix.
- *A redundant test*, in any language.
- *A decision record tied to file paths*, apart from repowise (AGPL).

### What this means for hone

Almost every code-quality check fits the two adapter slots that hone has
already, `scripts/lint.sh` and `scripts/typecheck.sh`. The right tool
differs per language and changes from year to year, so hone ships none. A
project that wants a third-copy gate calls jscpd from its `lint.sh`. So the
separate `scripts/duplication.sh` slot that I proposed earlier the same day
is not needed.

Three checks rest on concepts that only hone has, so no tool can supply
them. They are a list of the documents about changed code, read from the
`Governs:` lines, the size cap of a `src/<area>/`, and the `Cut:` line at
land. The four items that nobody has built as a detector stay with the
`consolidate-critic`.

## Where it landed

`docs/roadmap.md` rule 5 carries the principle. hone 0.55.0 carries the
three checks: `worktree.sh governed`, the oversized-area finding of the nag,
and the shape gate of land. `governed` stores no fingerprint. It reads the
diff of the change at hand, so it needs no lockfile and no re-stamp.
`templates/quality/README.md` maps each goal to the kinds of tool above.
