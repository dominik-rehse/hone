const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const quotes = require("../src/quotes.js");

function seed() {
  store.reset();
  quotes.clear();
  store.setMany([
    ["PEN-01", 250],
    ["PAD-02", 400],
  ]);
}

test("prices one line at the quantity asked for", () => {
  seed();
  const quote = quotes.getQuote("PEN-01", 4);
  assert.strictEqual(quote.unitCents, 250);
  assert.strictEqual(quote.totalCents, 1000);
});

test("gives a quantity its break", () => {
  seed();
  assert.strictEqual(quotes.getQuote("PEN-01", 10).totalCents, 2450);
});

test("has no quote for a sku with no price", () => {
  seed();
  assert.strictEqual(quotes.getQuote("NOPE", 1), null);
});

test("holds on to a quote it has already worked out", () => {
  seed();
  const first = quotes.getQuote("PEN-01", 4);
  assert.strictEqual(quotes.getQuote("PEN-01", 4), first);
  assert.strictEqual(quotes.memoSize(), 1);
});

test("works a quote out again once the sku is invalidated", () => {
  seed();
  const first = quotes.getQuote("PEN-01", 4);
  quotes.invalidate("PEN-01");
  assert.strictEqual(quotes.memoSize(), 0);
  assert.notStrictEqual(quotes.getQuote("PEN-01", 4), first);
});

test("leaves the other skus alone", () => {
  seed();
  const pad = quotes.getQuote("PAD-02", 2);
  quotes.getQuote("PEN-01", 2);
  quotes.invalidate("PEN-01");
  assert.strictEqual(quotes.getQuote("PAD-02", 2), pad);
});

test("totals a basket and leaves out what it cannot price", () => {
  seed();
  const basket = quotes.quoteBasket([
    { sku: "PEN-01", qty: 4 },
    { sku: "NOPE", qty: 1 },
    { sku: "PAD-02", qty: 2 },
  ]);
  assert.strictEqual(basket.lines.length, 2);
  assert.strictEqual(basket.totalCents, 1800);
});
