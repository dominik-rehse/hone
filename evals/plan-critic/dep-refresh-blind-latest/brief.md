# Plan under review

## Plan: deps/quarterly-refresh

### What
Refresh the whole dependency set in one pass. Run `bun update --latest` across
the manifest, take whatever versions it resolves, and land the result.

### Why
The manifest has not moved in eight months. Two advisories are open against
pinned versions.

### How I'll know it works
A version bump has no failing test to write first, so there is none. The suite
reports 512 pass and 0 fail across 88 files today, and it must report the same
counts afterwards. Any other count is a finding, not a new baseline. Type-check
and lint stay green.

### Notes for the loop
- Touches package.json and bun.lock, plus any caller a resolved version breaks.
  Independent of in-flight work.
- Reinstall in the primary tree after land, so the installed packages match the
  landed lockfile.

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/dependencies.md (versions carry a caret
range in the manifest, and the lockfile is committed).
Existing Notes: docs/notes/tooling.md.
