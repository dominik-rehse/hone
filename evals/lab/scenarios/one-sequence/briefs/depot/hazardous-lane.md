# Plan: depot/hazardous-lane

## What
The network takes hazardous goods under ADR from April. `book_parcel` in
`src/depot/booking.py` learns the flag `hazardous` on a parcel. A hazardous
parcel travels on the lane `adr`, whatever its service. Its promised day is
one day later than the same parcel without the flag. Three refusals come
with it, in this order. A hazardous parcel without a `un_number` raises
`a hazardous parcel needs a un_number`. One above 30000 g raises
`a hazardous parcel may not exceed 30000 g`. One in the zone `WORLD` raises
`the network takes no hazardous parcel outside the EU`. In every other
respect a hazardous parcel books as any parcel of its service, zone and
weight, and it is priced the same way.

## Why
Two industrial customers ship adhesives and lithium cells, about 400
parcels a month between them. The counter refuses all of them today. The
ADR lane is under contract from April, and the booking has to name it.

## How I'll know it works
Take a hazardous standard DE parcel of 2000 g with a `un_number`. Handed
over at BER on 2026-03-02 at minute 600, it books on the lane `adr` with
the promised day 2026-03-06. The same parcel without a `un_number` raises
`a hazardous parcel needs a un_number`. At 30001 g it raises
`a hazardous parcel may not exceed 30000 g`. In the zone `WORLD` it raises
`the network takes no hazardous parcel outside the EU`. Tests under
`tests/` pin the four, and `scripts/run-tests.sh --all` stays green.

## Notes for the loop
- Touches `src/depot/booking.py` and `tests/` only. Independent of
  in-flight work.
- Not a critical path.
