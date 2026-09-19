Review the change below.

## Plan: refunds/line-by-line

### What
The shop can only give a whole order back (`src/full-refund.js`). Add the
line-by-line path. `refund(orderId, lines, reason)` in a new `src/refund.js`
gives back the lines a customer names, by sku, and every line when they name
none. `src/refund-lines.js` works out what each named line comes back at, so an
order's discount lands on the lines it was taken off. Both write to the refund
store, the ledger and the payment, as the whole-order path does. Add
`src/handlers/refund.js` for the provider's `refund.succeeded` event, which is
how the shop hears of a refund the provider settled itself, and register it in
`src/app.js`.

### Why
Support gives a whole order back when one mug of four arrives broken, because
that is the only button there is. Finance found eleven of those last quarter,
worth £2,400 the shop did not owe. And a dispute the provider settles never
reaches our books at all, so the ledger and the provider's statement disagree
at every month end.

### How I'll know it works
One line of a two-line order comes back at what that line is worth. A refund
with no line named gives the whole order back. On a discounted order the line
comes back at what the customer paid for it, not at its list price. A sku the
order does not carry is turned down, and so is an order that is not there. A
`refund.succeeded` event reaches the refund store, the ledger and the payment,
and the customer hears about it. A refund the shop cannot mail out right now
still goes through.

### Notes for the loop
- Adds `src/refund.js`, `src/refund-lines.js`, `src/handlers/refund.js`,
  `tests/refund.test.js` and `tests/refund-webhook.test.js`. Touches
  `src/app.js`.
- Not a critical path. Finance checks the books against the provider's
  statement at month end either way.
