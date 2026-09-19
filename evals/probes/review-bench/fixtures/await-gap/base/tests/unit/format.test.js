const test = require("node:test");
const assert = require("node:assert");
const format = require("../../src/format.js");

test("writes whole cents as money", () => {
  assert.strictEqual(format.formatMoney(4800), "48.00 EUR");
  assert.strictEqual(format.formatMoney(0), "0.00 EUR");
});

test("writes a seat as the ticket prints it", () => {
  assert.strictEqual(format.formatSeat("A-1"), "row A, seat 1");
  assert.strictEqual(format.formatSeat("Z-99"), "seat Z-99");
});

test("writes a booking as one line", () => {
  assert.strictEqual(
    format.formatBooking({ seatId: "B-4", user: "ann", authId: null }),
    "row B, seat 4 for ann",
  );
});

test("puts a refusal into words", () => {
  assert.strictEqual(format.formatRefusal({ reason: "taken" }), "somebody else has that seat");
  assert.strictEqual(format.formatRefusal({ reason: "nonsense" }), "cannot do that: nonsense");
});

test("marks the taken seats on the house map", () => {
  const map = [
    { seatId: "A-1", user: "ann" },
    { seatId: "A-2", user: null },
    { seatId: "B-1", user: null },
  ];
  assert.strictEqual(format.formatSeatMap(map), ["A x.", "B ."].join("\n"));
});
