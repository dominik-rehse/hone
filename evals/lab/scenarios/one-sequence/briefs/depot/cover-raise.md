# Plan: depot/cover-raise

## What
Every parcel carries free insurance cover of 500.00 EUR today, held as
`FREE_COVER_CENTS` in `src/depot/pricing.py`. Raise it to 1000.00 EUR. A
parcel may name a `declared_cents` value. A parcel whose declared value is
above the free cover travels on the lane `secure`, whatever its service.
Its promised day is one day later than the same parcel without a declared
value. An economy parcel above the free cover raises
`economy carries no cover above the free cover`. A parcel whose declared
value is at or below the free cover books as it does today.

## Why
The carrier raised its own standard cover to 1000.00 EUR in the new
contract. So we pay for cover that we do not pass on. The secure lane is
the carrier's condition for anything above that cover, and about 80 parcels
a month declare more.

## How I'll know it works
A standard DE parcel of 2500 g with `declared_cents` 100000 books on the
lane `ground`. The same parcel with 100001 books on the lane `secure`.
Handed over at BER on 2026-03-02 at minute 600, that parcel carries the
promised day 2026-03-06 in place of 2026-03-05. An economy parcel with
100001 raises `economy carries no cover above the free cover`. The label of
a parcel then reads `cover 1000.00 EUR`. Tests under `tests/` pin the four,
and `scripts/run-tests.sh --all` stays green.

## Notes for the loop
- Touches `src/depot/pricing.py`, `src/depot/booking.py` and `tests/`
  only. Independent of in-flight work.
- Not a critical path.
