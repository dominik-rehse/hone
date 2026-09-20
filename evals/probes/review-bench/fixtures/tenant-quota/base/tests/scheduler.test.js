const test = require("node:test");
const assert = require("node:assert");
const queue = require("../src/queue.js");
const jobs = require("../src/jobs.js");
const tenants = require("../src/tenants.js");
const metrics = require("../src/metrics.js");
const scheduler = require("../src/scheduler.js");

test.beforeEach(() => {
  queue.clear();
  tenants.reset();
  metrics.reset();
  jobs.resetIds();
  tenants.add({ id: "acme" });
});

test("puts a job on the queue", () => {
  const answer = scheduler.submit("acme", "email", { to: "ops" });
  assert.strictEqual(answer.accepted, true);
  assert.strictEqual(answer.id, "job-1");
  assert.strictEqual(queue.size(), 1);
});

test("refuses a tenant it does not carry", () => {
  const answer = scheduler.submit("nobody", "email");
  assert.strictEqual(answer.accepted, false);
  assert.strictEqual(answer.reason, "unknown-tenant");
  assert.strictEqual(queue.size(), 0);
});

test("refuses a kind it does not run", () => {
  const answer = scheduler.submit("acme", "dance");
  assert.strictEqual(answer.accepted, false);
  assert.strictEqual(answer.reason, "bad-kind");
  assert.strictEqual(metrics.get("submit.bad-kind"), 1);
});

test("says so when the queue has no room", () => {
  queue.setCapacity(1);
  scheduler.submit("acme", "email");
  const answer = scheduler.submit("acme", "email");
  assert.strictEqual(answer.accepted, false);
  assert.strictEqual(answer.reason, "queue-full");
  assert.strictEqual(metrics.get("submit.queue-full"), 1);
});

test("counts what it took", () => {
  scheduler.submit("acme", "email");
  scheduler.submit("acme", "report");
  assert.strictEqual(metrics.get("submit.accepted"), 2);
});

test("reads its status", () => {
  scheduler.submit("acme", "email");
  assert.deepStrictEqual(scheduler.status(), {
    pending: 1,
    capacity: queue.DEFAULT_CAPACITY,
    tenants: 1,
  });
});
