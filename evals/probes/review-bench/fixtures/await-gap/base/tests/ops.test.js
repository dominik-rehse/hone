const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const lock = require("../src/lock.js");
const ops = require("../src/ops.js");

function fresh() {
  store.reset();
  lock.reset();
}

test("gives a seat back to the house", async () => {
  fresh();
  store.hold("A-1", "ann");
  const result = await ops.cancel("A-1", "ann");
  assert.strictEqual(result.ok, true);
  assert.strictEqual(store.holderOf("A-1"), null);
});

test("will not give back a seat that is not yours", async () => {
  fresh();
  store.hold("A-1", "ann");
  const result = await ops.cancel("A-1", "bo");
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "not-yours");
  assert.strictEqual(store.holderOf("A-1"), "ann");
});

test("moves a user to a free seat in their row", async () => {
  fresh();
  store.hold("A-1", "ann", "auth-1");
  const result = await ops.swap("A-1", "A-5", "ann");
  assert.strictEqual(result.ok, true);
  assert.strictEqual(store.holderOf("A-1"), null);
  assert.strictEqual(store.holderOf("A-5"), "ann");
  assert.strictEqual(result.booking.authId, "auth-1");
});

test("will not move a user out of the row they paid for", async () => {
  fresh();
  store.hold("A-1", "ann", "auth-1");
  const result = await ops.swap("A-1", "B-2", "ann");
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "other-row");
  assert.strictEqual(store.holderOf("A-1"), "ann");
});

test("will not move a user onto a seat somebody has", async () => {
  fresh();
  store.hold("A-1", "ann");
  store.hold("A-5", "bo");
  const result = await ops.swap("A-1", "A-5", "ann");
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "taken");
  assert.strictEqual(store.holderOf("A-1"), "ann");
});

test("lets only one of two who want the same free seat have it", async () => {
  fresh();
  store.hold("A-1", "ann");
  store.hold("A-2", "bo");
  const results = await Promise.all([
    ops.swap("A-1", "A-5", "ann"),
    ops.swap("A-2", "A-5", "bo"),
  ]);
  assert.strictEqual(results.filter((result) => result.ok).length, 1);
  assert.strictEqual(store.count(), 2);
});

test("shows the house row by row", () => {
  fresh();
  store.hold("A-1", "ann");
  const map = ops.seatMap();
  assert.strictEqual(map.length, 36);
  assert.strictEqual(map[0].user, "ann");
  assert.strictEqual(map[1].user, null);
});
