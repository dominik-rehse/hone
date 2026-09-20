# Plan: depot/cutoff-time

## What
`book_parcel` in `src/depot/booking.py` dispatches every parcel on the day
the depot took it. Add a same-day cutoff. The handover record gains a
`minute`, the minute of the day counted from midnight. A parcel handed over
at or before 16:00, which is minute 960, dispatches on the handover day. A
parcel handed over later dispatches on the next day. A dispatch day that
falls on a Saturday or a Sunday moves on to the next Monday. The promised
day counts from the dispatch day, as it does today.

## Why
The night sort leaves at 17:00. Counter staff tell a customer "it goes
today" right up to closing, and about 60 parcels a week miss that sort. Two
complaints last month named the promise on the receipt.

## How I'll know it works
A standard DE parcel of 2500 g handed over at BER on 2026-03-02 at minute
600 dispatches on 2026-03-02 and is promised on 2026-03-05. The same parcel
at minute 1000 dispatches on 2026-03-03 and is promised on 2026-03-06. The
same parcel handed over on Friday 2026-03-06 at minute 1000 dispatches on
Monday 2026-03-09. Tests under `tests/` pin the three, and
`scripts/run-tests.sh --all` stays green.

## Notes for the loop
- Touches `src/depot/booking.py` and `tests/` only. Independent of
  in-flight work.
- A Decision this change makes: one cutoff time for the whole network,
  because every depot feeds the same night sort.
- Not a critical path.
