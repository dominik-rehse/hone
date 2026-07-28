# Plan under review

## Plan: orders/reject-zero-quantity

### What
Reject an order line with a zero or negative quantity at parse time. Narrow the
`Quantity` type in src/orders/types.ts to a positive integer, make the parser in
src/orders/parse.ts return a typed error for a non-positive quantity, and extend
src/orders/parse.test.ts.

### Why
A partner feed sent quantity-0 lines last week; they reached fulfilment and
produced empty picking slips. The parser is the single entry point for order
data, so the fix belongs there.

### How I'll know it works
A parse test: quantity 0 and -3 each return `err("non-positive-quantity")`
naming the offending line; quantity 1 still parses. The narrowed type means a
constructed `Quantity` cannot hold 0, which the compiler enforces.

### Notes for the loop
- The three files are one change: the type is the fix, the parser is its only
  producer, the test pins it. None is separable into its own change.
- Independent of in-flight work.

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/order-intake.md (parse, don't validate: all
order data is narrowed to types at the feed boundary).
Existing Notes: docs/notes/orders.md.
