const test = require("node:test");
const assert = require("node:assert");
const tiers = require("../../src/tiers.js");

test("finds the steepest break a quantity earns", () => {
  assert.strictEqual(tiers.breakFor(100).off, 0.1);
  assert.strictEqual(tiers.breakFor(30).off, 0.05);
  assert.strictEqual(tiers.breakFor(10).off, 0.02);
});

test("has no break under the smallest quantity", () => {
  assert.strictEqual(tiers.breakFor(9), null);
  assert.strictEqual(tiers.breakFor(1), null);
});

test("totals a line without a break at the plain price", () => {
  assert.strictEqual(tiers.lineTotal(1000, 4), 4000);
});

test("takes the break off a line that earns one", () => {
  assert.strictEqual(tiers.lineTotal(1000, 10), 9800);
  assert.strictEqual(tiers.lineTotal(1000, 100), 90000);
});
