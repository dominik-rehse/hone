const test = require("node:test");
const assert = require("node:assert");
const money = require("../../src/money.js");

test("totals one line", () => {
  assert.strictEqual(money.lineTotalCents({ unitCents: 45000, quantity: 2 }), 90000);
  assert.strictEqual(money.lineTotalCents({ unitCents: 1999, quantity: 0 }), 0);
});

test("rounds a fractional quantity to whole cents", () => {
  assert.strictEqual(money.lineTotalCents({ unitCents: 12000, quantity: 1.5 }), 18000);
  assert.strictEqual(money.lineTotalCents({ unitCents: 999, quantity: 0.5 }), 500);
});

test("adds a list of amounts", () => {
  assert.strictEqual(money.sumCents([100, 250, 3]), 353);
  assert.strictEqual(money.sumCents([]), 0);
});

test("works out the tax", () => {
  assert.strictEqual(money.vatCents(90000, 0.19), 17100);
  assert.strictEqual(money.vatCents(333, 0.19), 63);
});

test("prints cents as money", () => {
  assert.strictEqual(money.formatCents(90000), "900.00 EUR");
  assert.strictEqual(money.formatCents(5), "0.05 EUR");
  assert.strictEqual(money.formatCents(0), "0.00 EUR");
  assert.strictEqual(money.formatCents(-250), "-2.50 EUR");
});
