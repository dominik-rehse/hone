# The transparent outcome, where no `Governs:` line helps. `seeded-prose`
# repeats a number in two documents that govern the changed path, so the list
# of `worktree.sh governed` hands both to the run. Here the repeats sit
# elsewhere: in the Note of a second area, and in a Decision with no
# `Governs:` line. The Plan changes the number and names neither document.
# Only a search for the value finds them. The second area calls the function,
# so its code and its tests stay true, and only its prose goes false.
mkdir -p src/shipping src/checkout docs/notes docs/decisions .plans/shipping
cat > src/shipping/rates.js <<'JS'
// The shipping cost of one order, in cents.
const FREE_FROM_CENTS = 10000;
const RATES = { DE: 490, AT: 690 };
const REST_OF_EU = 990;

function shippingCents(order) {
  if (order.totalCents >= FREE_FROM_CENTS) return 0;
  return RATES[order.country] ?? REST_OF_EU;
}

module.exports = { shippingCents };
JS
cat > src/shipping/rates.test.js <<'JS'
const test = require("node:test");
const assert = require("node:assert");
const { shippingCents } = require("./rates.js");

test("charges the flat rate of the country", () => {
  assert.strictEqual(shippingCents({ totalCents: 2500, country: "DE" }), 490);
  assert.strictEqual(shippingCents({ totalCents: 2500, country: "AT" }), 690);
});

test("ships free from the threshold on", () => {
  assert.strictEqual(shippingCents({ totalCents: 9999, country: "DE" }), 490);
  assert.strictEqual(shippingCents({ totalCents: 10000, country: "DE" }), 0);
});
JS
cat > src/checkout/summary.js <<'JS'
const { shippingCents } = require("../shipping/rates.js");

// The lines of the order summary that the checkout page shows.
function summaryLines(order) {
  const shipping = shippingCents(order);
  return [
    `Subtotal: ${(order.totalCents / 100).toFixed(2)} EUR`,
    shipping === 0 ? "Shipping: free" : `Shipping: ${(shipping / 100).toFixed(2)} EUR`,
    `Total: ${((order.totalCents + shipping) / 100).toFixed(2)} EUR`,
  ];
}

module.exports = { summaryLines };
JS
cat > src/checkout/summary.test.js <<'JS'
const test = require("node:test");
const assert = require("node:assert");
const { summaryLines } = require("./summary.js");

test("shows the shipping cost and adds it to the total", () => {
  assert.deepStrictEqual(summaryLines({ totalCents: 2500, country: "DE" }),
    ["Subtotal: 25.00 EUR", "Shipping: 4.90 EUR", "Total: 29.90 EUR"]);
});

test("shows free shipping as a word", () => {
  assert.deepStrictEqual(summaryLines({ totalCents: 40000, country: "DE" }),
    ["Subtotal: 400.00 EUR", "Shipping: free", "Total: 400.00 EUR"]);
});
JS
cat > docs/notes/shipping.md <<'MD'
# shipping

Governs: `src/shipping/`

Map: `rates.js` holds the whole rate table and the one function that reads it.

Invariant: a rate is a whole number of cents. Nothing in this area rounds.
MD
cat > docs/notes/checkout.md <<'MD'
# checkout

Governs: `src/checkout/`

Map: `summary.js` builds the lines of the order summary. It asks
`src/shipping/` for the shipping cost and never computes one.

Invariant: the total line is the subtotal plus the shipping line.

The summary shows the word "free" for an order of 100.00 EUR or more.
MD
cat > docs/decisions/free-shipping.md <<'MD'
# Free shipping from a threshold, and no coupon

We give free shipping from an order total on, and we send no free-shipping
coupon. A coupon needs a code field at checkout, and support answered 40
questions a month about codes that had expired. A threshold needs no input
from the customer. The threshold is 100.00 EUR.
MD
cat > .plans/shipping/free-from-150.md <<'PLAN'
# Plan: shipping/free-from-150

## What
`shippingCents` in `src/shipping/rates.js` ships an order free from 100.00
EUR on today. Raise that threshold to 150.00 EUR. An order of 149.99 EUR
pays the flat rate of its country, and an order of 150.00 EUR pays nothing.
The flat rates stay as they are.

## Why
The carrier raised its parcel prices by 11 percent in August. Finance
reports that free shipping between 100 and 150 EUR now loses money on two
orders out of three.

## How I'll know it works
`shippingCents({ totalCents: 14999, country: "DE" })` is 490, and with
`totalCents: 15000` it is 0. The unit test of the threshold pins both. The
test of the flat rates passes unchanged.

## Notes for the loop
- Touches `src/shipping/` only. Independent of in-flight work.
- Not a critical path.
PLAN
