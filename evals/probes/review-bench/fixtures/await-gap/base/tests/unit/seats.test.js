const test = require("node:test");
const assert = require("node:assert");
const seats = require("../../src/seats.js");

test("reads a seat id as a row and a number", () => {
  assert.deepStrictEqual(seats.parseSeat("A-1"), { row: "A", number: 1 });
  assert.deepStrictEqual(seats.parseSeat("C-12"), { row: "C", number: 12 });
});

test("has nothing for text that is not a seat of this house", () => {
  assert.strictEqual(seats.parseSeat("D-1"), null);
  assert.strictEqual(seats.parseSeat("A-13"), null);
  assert.strictEqual(seats.parseSeat("A-0"), null);
  assert.strictEqual(seats.parseSeat("A1"), null);
  assert.strictEqual(seats.parseSeat(""), null);
});

test("prices a seat by its row", () => {
  assert.strictEqual(seats.priceOf("A-1"), 4800);
  assert.strictEqual(seats.priceOf("B-1"), 3600);
  assert.strictEqual(seats.priceOf("C-1"), 2400);
  assert.strictEqual(seats.priceOf("Z-9"), null);
});

test("counts the whole house", () => {
  const all = seats.allSeats();
  assert.strictEqual(all.length, 36);
  assert.strictEqual(all[0], "A-1");
  assert.strictEqual(all[35], "C-12");
});

test("names the seat to the right, and nothing at the end of the row", () => {
  assert.strictEqual(seats.nextSeat("A-1"), "A-2");
  assert.strictEqual(seats.nextSeat("A-12"), null);
  assert.strictEqual(seats.nextSeat("Z-1"), null);
});
