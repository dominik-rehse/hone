# Plan: depot/billable-weight

## What
`price_parcel` in `src/depot/pricing.py` bills the weight part per started
kilo, at `WEIGHT_CENTS_PER_KILO`. Replace that with a billable weight. Add
`billable_weight(grams)` in the same file. It rounds the weight up to the
next 250 g, and it never gives less than 1000 g. For a weight that is not
positive it raises `a parcel needs a positive weight`.
`price_parcel` then bills 45 cents for each 250 g of the billable weight.
The base rate, the service uplift and the oversize surcharge stay as they
are.

## Why
The carrier moved to 250 g steps with a 1 kg minimum in its January
contract. We still bill per whole kilo, so a 1.1 kg parcel bills as 2 kg and
we overcharge. Support refunds about 30 of those a month.

## How I'll know it works
`billable_weight(1)` is 1000, `billable_weight(1000)` is 1000,
`billable_weight(1001)` is 1250, and `billable_weight(2501)` is 2750. A
standard DE parcel of 2501 g costs 985 cents. A standard DE parcel of 100 g
costs 670 cents. An economy WORLD parcel of 25100 g costs 6765 cents. Tests
under `tests/` pin them, and `scripts/run-tests.sh --all` stays green.

## Notes for the loop
- Touches `src/depot/pricing.py` and `tests/` only. Independent of
  in-flight work.
- Behaviour this change removes: the whole-kilo rounding and the constant
  `WEIGHT_CENTS_PER_KILO`, both in `src/depot/pricing.py`.
- Not a critical path.
