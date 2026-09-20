const test = require("node:test");
const assert = require("node:assert");
const queue = require("../src/queue.js");
const jobs = require("../src/jobs.js");
const tenants = require("../src/tenants.js");
const metrics = require("../src/metrics.js");
const scheduler = require("../src/scheduler.js");
const dispatch = require("../src/dispatch.js");

test.beforeEach(() => {
  queue.clear();
  tenants.reset();
  metrics.reset();
  dispatch.reset();
  jobs.resetIds();
  tenants.add({ id: "acme" });
});

test("takes a batch off the queue", () => {
  scheduler.submit("acme", "email");
  scheduler.submit("acme", "report");
  scheduler.submit("acme", "export");
  const batch = dispatch.nextBatch(2);
  assert.strictEqual(batch.length, 2);
  assert.strictEqual(dispatch.pending(), 1);
});

test("a batch bigger than the queue takes what there is", () => {
  scheduler.submit("acme", "email");
  assert.strictEqual(dispatch.nextBatch(10).length, 1);
  assert.strictEqual(dispatch.pending(), 0);
});

test("runs a job through its handler", () => {
  const seen = [];
  dispatch.handle("email", (job) => seen.push(job.id));
  scheduler.submit("acme", "email");
  const result = dispatch.run(dispatch.nextBatch(1)[0]);
  assert.strictEqual(result.ok, true);
  assert.deepStrictEqual(seen, ["job-1"]);
  assert.strictEqual(metrics.get("dispatch.ran"), 1);
});

test("lets a job with no handler go", () => {
  scheduler.submit("acme", "export");
  const result = dispatch.run(dispatch.nextBatch(1)[0]);
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "no-handler");
  assert.strictEqual(metrics.get("dispatch.unhandled"), 1);
});

test("keeps going when a handler throws", () => {
  dispatch.handle("email", () => {
    throw new Error("the mailer is down");
  });
  scheduler.submit("acme", "email");
  const result = dispatch.run(dispatch.nextBatch(1)[0]);
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "threw");
  assert.strictEqual(metrics.get("dispatch.failed"), 1);
});

test("runs a whole batch and counts it", () => {
  dispatch.handle("email", () => {});
  scheduler.submit("acme", "email");
  scheduler.submit("acme", "report");
  assert.deepStrictEqual(dispatch.runBatch(4), { ran: 1, refused: 1 });
});
