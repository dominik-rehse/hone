# Plan under review

## Plan: tooling/checkout-note

### What
Rename `docs/notes/test-tools.md` to `docs/notes/tooling.md`, because the file
has covered the whole toolchain for a year and its name still says tests. Add
one invariant to it: *A scratch checkout under `.checkouts/<name>/` runs no
test in the integration tier until `make vendor` has finished in that
checkout.*

### Why
Two people this month opened a scratch checkout, ran the integration tier, and
read the failure as a broken branch. A Note is where that belongs.

### How I'll know it works
`src/feeds/integration/rate-limit.test.ts` is what grounds the invariant. Its
lines 12 to 14 build `<checkout-root>/vendor/bin/wiremock` as an absolute path
from the directory of the test file. Its `beforeAll` at line 96 throws
`vendor/bin/wiremock is missing: run make vendor` when that path does not
exist. A fresh scratch checkout holds no `vendor/` directory of its own. A
docs test asserts that `docs/notes/test-tools.md` is gone and that no link in
the repository still names it.

### Notes for the loop
- Touches `docs/notes/` only. No code changes. Independent of in-flight work.

# Context

Open changes in flight: none.

Existing Decisions: none relevant.

Existing Notes: `docs/notes/test-tools.md`, the file this Plan renames:

```markdown
# test-tools

- `make vendor` downloads the pinned tool binaries into `vendor/bin/`.
- The runner resolves a vendored tool by walking up from the test file until
  it finds a `vendor/bin/` directory. So a test started anywhere below the
  primary checkout finds that checkout's binaries.
- A scratch checkout lives at `.checkouts/<name>/`, inside the primary
  checkout.
- `src/feeds/integration/` holds the integration tier: eleven test files. One
  of them, `rate-limit.test.ts`, builds its tool path itself.

Invariant: every pinned tool version lives in `tools.lock`, and nowhere else.
```
