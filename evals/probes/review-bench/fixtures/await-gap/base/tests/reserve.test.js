const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const ops = require("../src/ops.js");

test("holds a free seat for a user", () => {
  store.reset();
  const result = ops.reserve("A-1", "ann");
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.booking.user, "ann");
  assert.strictEqual(result.price, 4800);
  assert.strictEqual(store.holderOf("A-1"), "ann");
});

test("refuses a seat somebody already holds", () => {
  store.reset();
  ops.reserve("A-1", "ann");
  const result = ops.reserve("A-1", "bo");
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "taken");
  assert.strictEqual(store.holderOf("A-1"), "ann");
});

test("refuses a seat the house has not", () => {
  store.reset();
  const result = ops.reserve("Z-99", "ann");
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "no-such-seat");
});

test("prices a seat by its row", () => {
  store.reset();
  assert.strictEqual(ops.reserve("B-2", "ann").price, 3600);
  assert.strictEqual(ops.reserve("C-3", "ann").price, 2400);
});

test("lists the seats a user holds in the order they took them", () => {
  store.reset();
  ops.reserve("B-4", "ann");
  ops.reserve("A-1", "ann");
  assert.deepStrictEqual(
    ops.bookingsOf("ann").map((booking) => booking.seatId),
    ["B-4", "A-1"],
  );
});

test("counts the seats still to be had", () => {
  store.reset();
  const all = ops.seatsLeft();
  ops.reserve("A-1", "ann");
  assert.strictEqual(ops.seatsLeft(), all - 1);
});
