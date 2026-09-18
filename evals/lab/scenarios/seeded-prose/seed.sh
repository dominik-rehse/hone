# The transparent outcome. The area already carries prose that repeats its
# code: a Note that grew a list of behaviours, and a Decision whose second
# paragraph restates the function. Each also carries something worth keeping:
# the Note's map and invariant, and the Decision's reason. The Plan changes the
# one number that both repeats name, and it says nothing about the docs. So
# after the change each repeat is cut, updated by hand, or stale. The Note
# stays under the nag's size cap, so that consolidate and its critic are what
# the scenario measures.
mkdir -p src/shipping docs/notes docs/decisions .plans/shipping
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

test("charges the rest-of-EU rate for a country with no rate of its own", () => {
  assert.strictEqual(shippingCents({ totalCents: 2500, country: "FR" }), 990);
});

test("ships free from the threshold on", () => {
  assert.strictEqual(shippingCents({ totalCents: 9999, country: "DE" }), 490);
  assert.strictEqual(shippingCents({ totalCents: 10000, country: "DE" }), 0);
});
JS
cat > docs/notes/shipping.md <<'MD'
# shipping

Governs: `src/shipping/`

Map: `rates.js` holds the whole rate table and the one function that reads it.

Invariant: a rate is a whole number of cents. Nothing in this area rounds.

## Behaviour

- An order of 100.00 EUR or more ships free.
- The threshold compares the order total before shipping.
- An order to Germany costs 4.90 EUR.
- An order to Austria costs 6.90 EUR.
- An order to any other country costs 9.90 EUR.
MD
cat > docs/decisions/shipping-rates.md <<'MD'
# Flat shipping rates per country

Governs: `src/shipping/rates.js`

We charge one flat rate per country and nothing by weight. The carrier
contract bills us a flat rate per parcel and country. A price by weight would
only add a gap between what we charge and what we pay. We rejected weight
bands in 2025, when a trial showed that 94 percent of our parcels fall in
the lowest band.

`shippingCents` looks the country up in `RATES` and falls back to
`REST_OF_EU`. It returns 0 when `order.totalCents` is at least
`FREE_FROM_CENTS`, which is 10000, so an order of 100.00 EUR ships free.
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
two tests of the flat rates pass unchanged.

## Notes for the loop
- Touches `src/shipping/` only. Independent of in-flight work.
- Not a critical path.
PLAN
