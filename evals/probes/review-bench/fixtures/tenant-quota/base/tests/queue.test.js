const test = require("node:test");
const assert = require("node:assert");
const queue = require("../src/queue.js");

const job = (id) => ({ id, kind: "email", tenantId: "acme" });

test.beforeEach(() => queue.clear());

test("takes jobs oldest first", () => {
  queue.push(job("a"));
  queue.push(job("b"));
  assert.strictEqual(queue.take().id, "a");
  assert.strictEqual(queue.take().id, "b");
  assert.strictEqual(queue.take(), null);
});

test("says how many are waiting", () => {
  assert.strictEqual(queue.size(), 0);
  queue.push(job("a"));
  assert.strictEqual(queue.size(), 1);
  assert.strictEqual(queue.peek().id, "a");
});

test("says no once it is full", () => {
  queue.setCapacity(2);
  assert.strictEqual(queue.push(job("a")), true);
  assert.strictEqual(queue.push(job("b")), true);
  assert.strictEqual(queue.push(job("c")), false);
  assert.strictEqual(queue.size(), 2);
  assert.strictEqual(queue.isFull(), true);
});

test("has room again once a job comes off", () => {
  queue.setCapacity(1);
  queue.push(job("a"));
  assert.strictEqual(queue.push(job("b")), false);
  queue.take();
  assert.strictEqual(queue.push(job("b")), true);
});

test("hands out a copy of what is waiting", () => {
  queue.push(job("a"));
  const seen = queue.all();
  seen.push(job("b"));
  assert.strictEqual(queue.size(), 1);
});

test("puts a whole list in place of the one it had", () => {
  queue.push(job("a"));
  queue.push(job("b"));
  assert.strictEqual(queue.replace([job("c")]), 1);
  assert.deepStrictEqual(
    queue.all().map((one) => one.id),
    ["c"],
  );
});
