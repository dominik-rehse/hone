Review the change below.

## Plan: booking/preauthorize-on-reserve

### What
`reserve(seatId, user)` writes a seat to a user and nothing else. Put the card
in front of the write. Add `src/payments.js`, the gateway the till talks to. It
carries a stand-in for the test hall, which answers after a set delay. The
stand-in can turn a card down. It can also hold less than the till asked for.
`reserve` becomes async.
It asks the gateway to put the seat's price aside, and it refuses a turned down
card. It gives a hold back when the gateway held less than the price. The
booking keeps the hold's id. Add `formatConfirmation` to `src/format.js` for the
slip the till prints, and words for the two new refusals.

### Why
The house writes a seat first and takes the money at the door. Fourteen seats
last season went to people whose card would not pay, and the row stayed empty
while the queue outside was turned away.

### How I'll know it works
A free seat comes back held, priced by its row, with the gateway's hold id on
the booking. A seat somebody has is refused, and the card is not asked. A
turned down card leaves the seat free. A card that holds less than the price
leaves the seat free and nothing outstanding at the gateway. A slow gateway
changes nothing but the wait. The slip reads as the seat, the money and the
hold.

### Notes for the loop
- Adds `src/payments.js` and touches `src/ops.js`, `src/format.js`,
  `tests/reserve.test.js` and `tests/unit/format.test.js`.
- `cancel` and `swap` keep the shape they have.
- Not a critical path yet. The door still checks a ticket against the store.
