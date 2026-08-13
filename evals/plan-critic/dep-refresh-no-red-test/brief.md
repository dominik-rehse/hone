# Plan under review

## Plan: toolchain/lint-major-bump

### What
Move the linter from 1.9.4 to 2.1.0. Bump that one package explicitly at the new
major. Run the tool's own config migrator (`bunx <linter> migrate --write`) to
rewrite `lint.config.json`, then fix the findings the new version reports. No
production behaviour changes.

### Why
The 1.x line goes end-of-life next month and stops getting rule updates. Two
recent bugs would have been caught by rules 2.x adds.

### How I'll know it works
A version bump has no failing test to write first, so there is none, and no test
here asserts a version string. The evidence is the suite unchanged plus the
probe's report matched exactly. The suite reports 328 pass and 0 fail across 64
files today, and it must report the same counts after the bump. Any other count
is a finding, not a new baseline. The probe (the new linter run in a throwaway
detached worktree) reported 12 findings, listed by file and line in the
reference below. Treat that file as the expected report, not the authority: a
13th finding, or a different file, is something to report, not to accept. A cold
install in a scratch worktree must leave the lockfile unchanged.

### References
- .plans/toolchain/lint-major-bump/findings.txt — the 12 findings 2.1.0 reports
  against today's tree, by file and line.

### Notes for the loop
- Touches package.json, bun.lock, lint.config.json, and the files the 12
  findings name. Independent of in-flight work.
- Reinstall in the primary tree after land, so the installed packages match the
  landed lockfile.

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/toolchain.md (one linter for the repo, its
config committed at the root, no per-directory overrides).
Existing Notes: docs/notes/tooling.md.
