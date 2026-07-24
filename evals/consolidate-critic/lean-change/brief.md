# Change under review (consolidate step)

## Plan (in hand, to be deleted): export/csv-escaping
Escape CSV fields per RFC 4180.

## Diff summary
- src/export/csv.ts: `escapeField(f)` wraps a field in quotes when it contains
  `, " \n \r` and doubles embedded quotes; `toCsv` now calls it per field.
- src/export/csv.test.ts: example tests for each special char; a property test
  `parse(toCsv(rows)) == rows`; a golden-file test.

## What this change left behind (durable layer)
- No new Decision (the RFC-4180 choice is self-evident from the code and the
  property test; there was no alternative worth recording).
- docs/notes/export.md unchanged (still: "Export area serializes records to CSV;
  invariant: output round-trips through a standard CSV parser." — one map line,
  one invariant).
- No tests pruned (none were redundant).

## Types / abstractions touched
- `escapeField` is a single small pure function with one caller. No new generic.
