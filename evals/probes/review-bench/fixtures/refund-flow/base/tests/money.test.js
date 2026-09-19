const test = require("node:test");
const assert = require("node:assert");
const money = require("../src/money.js");

test("adds up a list of amounts", () => {
  assert.strictEqual(money.sum([1250, 300, 5]), 1555);
  assert.strictEqual(money.sum([]), 0);
});

test("splits an amount that divides evenly", () => {
  assert.deepStrictEqual(money.allocate(900, [1000, 2000]), [300, 600]);
});

test("gives the odd cents to the largest shares", () => {
  assert.deepStrictEqual(money.allocate(100, [1000, 1000, 1000]), [34, 33, 33]);
  assert.strictEqual(money.sum(money.allocate(100, [1000, 1000, 1000])), 100);
});

test("splits an amount over weights of their own sizes", () => {
  const shares = money.allocate(1000, [700, 200, 100]);
  assert.deepStrictEqual(shares, [700, 200, 100]);
});

test("splits nothing and splits over nothing", () => {
  assert.deepStrictEqual(money.allocate(0, [10, 20]), [0, 0]);
  assert.deepStrictEqual(money.allocate(500, []), []);
});

test("splits evenly when the weights are all nothing", () => {
  assert.deepStrictEqual(money.allocate(10, [0, 0, 0]), [4, 3, 3]);
});

test("writes cents out for a customer", () => {
  assert.strictEqual(money.format(1250), "$12.50");
  assert.strictEqual(money.format(7), "$0.07");
  assert.strictEqual(money.format(-1250), "-$12.50");
});
