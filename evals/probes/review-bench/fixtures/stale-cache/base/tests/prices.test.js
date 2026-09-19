const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const quotes = require("../src/quotes.js");
const prices = require("../src/prices.js");
const catalog = require("../src/catalog.js");

function seed() {
  return catalog.loadInitial({ "PEN-01": 250, "PAD-02": 400 });
}

test("loads the price book the service starts from", () => {
  assert.strictEqual(seed(), 2);
  assert.strictEqual(store.get("PEN-01"), 250);
  assert.strictEqual(quotes.memoSize(), 0);
});

test("reports what a price was and what it is now", () => {
  seed();
  assert.deepStrictEqual(prices.updatePrice("PEN-01", 300), {
    sku: "PEN-01",
    before: 250,
    after: 300,
  });
  assert.strictEqual(store.get("PEN-01"), 300);
});

test("takes a sku off the list", () => {
  seed();
  assert.strictEqual(prices.retire("PAD-02"), true);
  assert.strictEqual(store.has("PAD-02"), false);
  assert.strictEqual(prices.retire("PAD-02"), false);
});

test("moves a price by a percentage, up and down", () => {
  seed();
  assert.strictEqual(prices.repriceByPercent("PEN-01", 10).after, 275);
  assert.strictEqual(prices.repriceByPercent("PEN-01", -10).after, 248);
});

test("has nothing to reprice for an unknown sku", () => {
  seed();
  assert.strictEqual(prices.repriceByPercent("NOPE", 10), null);
});

test("writes one line of the price list", () => {
  seed();
  assert.strictEqual(prices.priceLine("PEN-01"), "PEN-01 2.50");
  assert.strictEqual(prices.priceLine("NOPE"), "NOPE -");
});
