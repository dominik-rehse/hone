const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");

test("writes a seat to a user and reads it back", () => {
  store.reset();
  const booking = store.hold("A-1", "ann");
  assert.strictEqual(booking.seatId, "A-1");
  assert.strictEqual(booking.user, "ann");
  assert.strictEqual(booking.authId, null);
  assert.strictEqual(store.holderOf("A-1"), "ann");
  assert.strictEqual(store.count(), 1);
});

test("has nobody on a seat nobody took", () => {
  store.reset();
  assert.strictEqual(store.holderOf("A-1"), null);
  assert.strictEqual(store.bookingOf("A-1"), null);
});

test("refuses a seat the house has not", () => {
  store.reset();
  assert.throws(() => store.hold("Z-99", "ann"), /no such seat/);
});

test("writes the later holder over the earlier one", () => {
  store.reset();
  store.hold("A-1", "ann");
  store.hold("A-1", "bo");
  assert.strictEqual(store.holderOf("A-1"), "bo");
  assert.strictEqual(store.count(), 1);
});

test("takes a seat back, and says whether anybody had it", () => {
  store.reset();
  store.hold("A-1", "ann");
  assert.strictEqual(store.release("A-1"), true);
  assert.strictEqual(store.release("A-1"), false);
  assert.strictEqual(store.holderOf("A-1"), null);
});

test("lists the seats one user holds, in the order they took them", () => {
  store.reset();
  store.hold("B-4", "ann");
  store.hold("A-1", "bo");
  store.hold("C-7", "ann");
  assert.deepStrictEqual(
    store.heldBy("ann").map((booking) => booking.seatId),
    ["B-4", "C-7"],
  );
});

test("keeps the card reference it was given", () => {
  store.reset();
  assert.strictEqual(store.hold("A-1", "ann", "auth-3").authId, "auth-3");
});
