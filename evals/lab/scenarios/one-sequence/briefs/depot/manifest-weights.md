# Plan: depot/manifest-weights

## What
`render_manifest` in `src/depot/manifest.py` prints one line per booking,
with the parcel, the lane and the promised day. Add the billable weight of
each parcel. A parcel line gains that weight in kilograms to two decimals,
right aligned in a field of 8, then ` kg  `, then the promised day. The
last line gains the billable total of the run. It reads
`<n> parcel(s), <total> kg billable`, with the total in kilograms to two
decimals. A billable weight is the weight the depot bills: the gram weight
rounded up to the next 250 g, and never under 1000 g.

## Why
The driver signs for a weight, and the depot bills the customer for a
weight. The two come from different sheets today. Three disputes last
quarter were about a weight the driver never saw.

## How I'll know it works
Take a run `M-1` at BER on 2026-03-02 over two bookings. The first is a
parcel `P-1` of 2501 g on the lane `ground`, promised on 2026-03-05. The
second is a parcel `P-2` of 800 g on the lane `air`, promised on
2026-03-04. `render_manifest` renders exactly these four lines:

```
Manifest M-1 | Berlin Sud | 2026-03-02
P-1         ground      2.75 kg  2026-03-05
P-2         air         1.00 kg  2026-03-04
2 parcel(s), 3.75 kg billable
```

Tests under `tests/` pin it, and `scripts/run-tests.sh --all` stays green.

## Notes for the loop
- Touches `src/depot/manifest.py` and `tests/` only. Independent of
  in-flight work.
- Not a critical path.
