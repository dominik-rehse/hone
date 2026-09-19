const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");

test("holds a price and gives it back", () => {
  store.reset();
  store.set("PEN-01", 250);
  assert.strictEqual(store.get("PEN-01"), 250);
  assert.strictEqual(store.has("PEN-01"), true);
});

test("has nothing for a sku it never heard of", () => {
  store.reset();
  assert.strictEqual(store.get("NOPE"), null);
  assert.strictEqual(store.has("NOPE"), false);
});

test("writes many prices at once and counts them", () => {
  store.reset();
  const written = store.setMany([
    ["PEN-01", 250],
    ["PAD-02", 400],
  ]);
  assert.strictEqual(written, 2);
  assert.strictEqual(store.get("PAD-02"), 400);
  assert.strictEqual(store.size(), 2);
});

test("lets a later write win", () => {
  store.reset();
  store.set("PEN-01", 250);
  store.setMany([["PEN-01", 275]]);
  assert.strictEqual(store.get("PEN-01"), 275);
  assert.strictEqual(store.size(), 1);
});

test("removes a sku and says whether it was there", () => {
  store.reset();
  store.set("PEN-01", 250);
  assert.strictEqual(store.remove("PEN-01"), true);
  assert.strictEqual(store.remove("PEN-01"), false);
  assert.deepStrictEqual(store.skus(), []);
});
