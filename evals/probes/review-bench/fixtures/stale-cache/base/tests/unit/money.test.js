const test = require("node:test");
const assert = require("node:assert");
const money = require("../../src/money.js");

test("reads a plain amount as whole cents", () => {
  assert.strictEqual(money.parseAmount("12.50"), 1250);
  assert.strictEqual(money.parseAmount("7"), 700);
  assert.strictEqual(money.parseAmount(" 0.05 "), 5);
});

test("reads one decimal place as tens of cents", () => {
  assert.strictEqual(money.parseAmount("1.5"), 150);
});

test("has nothing for text that is not an amount", () => {
  assert.strictEqual(money.parseAmount("twelve"), null);
  assert.strictEqual(money.parseAmount("12.505"), null);
  assert.strictEqual(money.parseAmount("-3.00"), null);
  assert.strictEqual(money.parseAmount(""), null);
});

test("writes cents back as an amount", () => {
  assert.strictEqual(money.formatCents(1250), "12.50");
  assert.strictEqual(money.formatCents(5), "0.05");
  assert.strictEqual(money.formatCents(-250), "-2.50");
});
