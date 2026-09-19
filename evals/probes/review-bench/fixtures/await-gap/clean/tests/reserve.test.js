const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const lock = require("../src/lock.js");
const payments = require("../src/payments.js");
const ops = require("../src/ops.js");

function fresh() {
  store.reset();
  lock.reset();
  payments.reset();
}

test("holds a free seat for a user once the card clears", async () => {
  fresh();
  const result = await ops.reserve("A-1", "ann");
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.booking.user, "ann");
  assert.strictEqual(result.price, 4800);
  assert.strictEqual(store.holderOf("A-1"), "ann");
});

test("writes the gateway's hold onto the booking", async () => {
  fresh();
  const result = await ops.reserve("A-1", "ann");
  assert.strictEqual(result.booking.authId, "auth-1");
  assert.deepStrictEqual(
    payments.outstandingAuths().map((auth) => auth.cents),
    [4800],
  );
});

test("refuses a seat somebody already holds", async () => {
  fresh();
  await ops.reserve("A-1", "ann");
  const result = await ops.reserve("A-1", "bo");
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "taken");
  assert.strictEqual(store.holderOf("A-1"), "ann");
});

test("asks the card for nothing when the seat is gone", async () => {
  fresh();
  await ops.reserve("A-1", "ann");
  await ops.reserve("A-1", "bo");
  assert.strictEqual(payments.outstandingAuths().length, 1);
});

test("refuses a seat the house has not", async () => {
  fresh();
  const result = await ops.reserve("Z-99", "ann");
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "no-such-seat");
  assert.strictEqual(payments.outstandingAuths().length, 0);
});

test("refuses a turned down card and leaves the seat free", async () => {
  fresh();
  payments.declineCard("ann");
  const result = await ops.reserve("A-1", "ann");
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "declined");
  assert.strictEqual(result.decline, "card-declined");
  assert.strictEqual(store.holderOf("A-1"), null);
});

test("gives the hold back when the card would not take the whole price", async () => {
  fresh();
  payments.underfundCard("ann");
  const result = await ops.reserve("B-2", "ann");
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "short-hold");
  assert.strictEqual(store.holderOf("B-2"), null);
  assert.deepStrictEqual(payments.outstandingAuths(), []);
});

test("books against a gateway that takes its time", async () => {
  fresh();
  payments.setDelay(15);
  const result = await ops.reserve("C-3", "ann");
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.price, 2400);
});

test("prices a seat by its row", async () => {
  fresh();
  assert.strictEqual((await ops.reserve("B-2", "ann")).price, 3600);
  assert.strictEqual((await ops.reserve("C-3", "ann")).price, 2400);
});

test("lists the seats a user holds in the order they took them", async () => {
  fresh();
  await ops.reserve("B-4", "ann");
  await ops.reserve("A-1", "ann");
  assert.deepStrictEqual(
    ops.bookingsOf("ann").map((booking) => booking.seatId),
    ["B-4", "A-1"],
  );
});

test("counts the seats still to be had", async () => {
  fresh();
  const all = ops.seatsLeft();
  await ops.reserve("A-1", "ann");
  assert.strictEqual(ops.seatsLeft(), all - 1);
});
