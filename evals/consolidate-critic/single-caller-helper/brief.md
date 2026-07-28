# Change under review (consolidate step)

## Plan (in hand, to be deleted): report/quarter-boundaries
Fix the quarterly report's off-by-one on quarter boundaries.

## Diff summary
- src/report/quarter.ts: extracts `quarterStart(date)`, a five-line pure
  function returning the first instant of the date's quarter; the report
  builder now calls it instead of inlining the arithmetic.
- src/report/quarter.test.ts: boundary tests (Mar 31 23:59, Apr 1 00:00, leap
  Feb 29) and one example per quarter.

## What this change left behind (durable layer)
- No new Decision (the fix is visible in the code and pinned by the boundary
  tests).
- docs/notes/report.md unchanged (map + one invariant: "a row lands in exactly
  one quarter").
- No tests pruned (none were redundant).

## Types / abstractions touched
- `quarterStart` is a small pure function with a single caller, the report
  builder. It is not generic and takes no configuration; it exists so the
  boundary tests can pin the arithmetic directly.
