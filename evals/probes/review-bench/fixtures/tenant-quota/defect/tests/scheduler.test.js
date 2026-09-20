const test = require("node:test");
const assert = require("node:assert");
const queue = require("../src/queue.js");
const jobs = require("../src/jobs.js");
const tenants = require("../src/tenants.js");
const metrics = require("../src/metrics.js");
const quota = require("../src/quota.js");
const scheduler = require("../src/scheduler.js");

test.beforeEach(() => {
  queue.clear();
  tenants.reset();
  metrics.reset();
  quota.reset();
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

test("refuses a free tenant past its limit", () => {
  const limit = tenants.limitFor(tenants.get("acme"));
  for (let i = 0; i < limit; i += 1) {
    assert.strictEqual(scheduler.submit("acme", "email").accepted, true);
  }
  const answer = scheduler.submit("acme", "email");
  assert.strictEqual(answer.accepted, false);
  assert.strictEqual(answer.reason, "over-quota");
  assert.strictEqual(answer.limit, limit);
  assert.strictEqual(metrics.get("submit.over-quota"), 1);
  assert.strictEqual(queue.size(), limit);
});

test("a paid tenant goes a long way further than a free one", () => {
  tenants.add({ id: "mint", plan: "paid" });
  for (let i = 0; i < 20; i += 1) {
    scheduler.submit("mint", "email");
  }
  assert.strictEqual(scheduler.submit("mint", "email").accepted, true);
  assert.strictEqual(scheduler.remaining("mint"), 179);
});

test("the answer says how much of the window has gone", () => {
  const answer = scheduler.submit("acme", "email");
  assert.strictEqual(answer.used, 1);
  assert.strictEqual(answer.limit, 5);
  assert.strictEqual(scheduler.remaining("acme"), 4);
});

test("a new window lets a refused tenant back in", () => {
  for (let i = 0; i < 6; i += 1) {
    scheduler.submit("acme", "email");
  }
  assert.strictEqual(scheduler.submit("acme", "email").reason, "over-quota");
  quota.resetWindow(Date.now());
  assert.strictEqual(scheduler.submit("acme", "email").accepted, true);
});

test("a job carries the tenant's priority", () => {
  tenants.add({ id: "mint", plan: "paid" });
  scheduler.submit("acme", "email");
  scheduler.submit("mint", "email");
  const [first, second] = queue.all();
  assert.strictEqual(first.priority, 0);
  assert.strictEqual(second.priority, 10);
});

test("a tenant it does not carry has no window to read", () => {
  assert.throws(() => scheduler.remaining("nobody"), RangeError);
});

test("a plan the table does not carry reads as free", () => {
  tenants.add({ id: "odd", plan: "constructor" });
  assert.strictEqual(tenants.limitFor(tenants.get("odd")), 5);
  assert.strictEqual(tenants.priorityFor(tenants.get("odd")), 0);
});

test("reads its status", () => {
  scheduler.submit("acme", "email");
  assert.deepStrictEqual(scheduler.status(), {
    pending: 1,
    capacity: queue.DEFAULT_CAPACITY,
    tenants: 1,
    quota: { acme: 1 },
  });
});
