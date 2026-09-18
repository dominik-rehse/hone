# Plan under review

## Plan: cart/free-shipping-threshold

### What
Add one rule to `shippingCost` in `src/cart/shipping.ts`, in front of the
zone table: an order with goods of 50.00 or more ships free, in every zone.
The zone table and its prices stay as they are.

### Why
The spring catalogue is out and promises free shipping from 50.00 of goods.
The checkout still charges for it, and support refunds about thirty orders a
week by hand.

### How I'll know it works
Goods of 49.99 to zone 2 still cost what the zone table says. Goods of 50.00
to zone 2 cost 0. Unit tests pin both, and the existing zone tests pass
unchanged.

### Notes for the loop
- Touches `src/cart/` only. Independent of in-flight work.
- Critical path: this is an amount we charge.

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/shipping-zones.md (why the zones follow the
carrier's contract and not the country list).
Existing Notes: docs/notes/cart.md.
