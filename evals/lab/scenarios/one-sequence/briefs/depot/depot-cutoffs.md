# Plan: depot/depot-cutoffs

## What
`book_parcel` in `src/depot/booking.py` uses one cutoff minute for the
whole network. Give each depot its own. BER cuts off at 15:30, which is
minute 930. HAM cuts off at 17:00, minute 1020. MUC cuts off at 18:15,
minute 1095. The one network cutoff goes: every depot the network serves
now has a cutoff of its own. Add the Saturday sort as well. A dispatch day
that falls on a Saturday stands for an express parcel. Every other parcel
moves on to the Monday, and a Sunday still moves on to the Monday for every
parcel.

## Why
The three depots stopped sharing one night sort in January. BER feeds the
Leipzig hub an hour earlier now, and MUC loads a late trailer of its own.
One cutoff for all three sends about 200 BER parcels a week onto a sort
they miss. It also holds MUC parcels back that would still make theirs. The
Saturday sort has run for express since February, and the booking does not
know about it.

## How I'll know it works
Take a standard DE parcel of 2500 g handed over on 2026-03-02. At BER it
dispatches on 2026-03-02 at minute 929, and on 2026-03-03 at minute 931. At
HAM the pair is minute 1020 and minute 1021. At MUC it is minute 1095 and
minute 1096. An express DE parcel handed over at BER on Friday 2026-03-06
at minute 1000 dispatches on Saturday 2026-03-07. A standard one dispatches
on Monday 2026-03-09. Tests under `tests/` pin them, and
`scripts/run-tests.sh --all` stays green.

## Notes for the loop
- Touches `src/depot/booking.py` and `tests/` only. Independent of
  in-flight work.
- Behaviour this change removes: the single network cutoff, in
  `src/depot/booking.py`.
- Not a critical path.
