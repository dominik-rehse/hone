# Plan under review

## Plan: checkout/one-click

### What
Add a one-click checkout button to the cart page. When a signed-in user with a
saved card clicks it, the order is placed and a confirmation screen renders in
the browser without a further page load.

### Why
The current checkout is a four-step form; analytics show a 38% drop-off between
the cart and the first form step. Two enterprise customers asked for a faster path.

### How I'll know it works
A unit test asserts that `placeOrder(cart, savedCard)` returns an `Order` object
with `status: "placed"`.

### Notes for the loop
- Touches src/checkout/one-click.ts and the cart component.
- Independent of in-flight work.

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/checkout-flow.md.
Existing Notes: docs/notes/checkout.md.
