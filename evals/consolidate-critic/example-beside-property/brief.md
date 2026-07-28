# Change under review (consolidate step)

## Plan (in hand, to be deleted): url/normalize
Normalize URLs before dedup so equivalent URLs collapse to one entry.

## Diff summary
- src/url/normalize.ts: lowercases scheme and host, strips default ports,
  resolves dot-segments, sorts query parameters.
- src/url/normalize.test.ts, three kinds of test on the same function:
  - example tests: `HTTP://Ex.com:80/a/../b?z=1&a=2` →
    `http://ex.com/b?a=2&z=1`, plus five more specific pairs;
  - a property test: normalize is idempotent,
    `normalize(normalize(u)) == normalize(u)` over generated URLs;
  - a golden test: a checked-in list of 40 raw URLs and their normalized forms.

## What this change left behind (durable layer)
- No new Decision.
- docs/notes/url.md unchanged.
- No tests pruned.

## Types / abstractions touched
- none new.
