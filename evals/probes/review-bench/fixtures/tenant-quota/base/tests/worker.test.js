const test = require("node:test");
const assert = require("node:assert");
const queue = require("../src/queue.js");
const jobs = require("../src/jobs.js");
const tenants = require("../src/tenants.js");
const metrics = require("../src/metrics.js");
const timers = require("../src/timers.js");
const scheduler = require("../src/scheduler.js");
const dispatch = require("../src/dispatch.js");
const worker = require("../src/worker.js");

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test.beforeEach(() => {
  worker.stop();
  timers.shutdown();
  queue.clear();
  tenants.reset();
  metrics.reset();
  dispatch.reset();
  jobs.resetIds();
  tenants.add({ id: "acme" });
});

test.after(() => {
  worker.stop();
  timers.shutdown();
});

test("a tick runs what is waiting", () => {
  dispatch.handle("email", () => {});
  scheduler.submit("acme", "email");
  assert.deepStrictEqual(worker.tick(4), { ran: 1, refused: 0 });
  assert.strictEqual(queue.size(), 0);
});

test("starts once and stops once", () => {
  const handle = worker.start(1000);
  assert.strictEqual(worker.start(1000), handle);
  assert.strictEqual(worker.isRunning(), true);
  assert.strictEqual(worker.stop(), true);
  assert.strictEqual(worker.stop(), false);
});

test("a started worker is a timer this process knows about", () => {
  assert.strictEqual(timers.count(), 0);
  worker.start(1000);
  assert.strictEqual(timers.count(), 1);
  worker.stop();
  assert.strictEqual(timers.count(), 0);
});

test("a shutdown puts a running worker out", async () => {
  dispatch.handle("email", () => {});
  worker.start(5);
  await sleep(30);
  const ticks = metrics.get("worker.ticks");
  assert.ok(ticks > 0, "the worker ticked while it ran");
  timers.shutdown();
  await sleep(40);
  assert.strictEqual(metrics.get("worker.ticks"), ticks);
  worker.stop();
});

test("a flush is a timer this process knows about too", () => {
  const seen = [];
  metrics.startFlush(1000, (snapshot) => seen.push(snapshot));
  assert.strictEqual(timers.count(), 1);
  timers.shutdown();
  assert.strictEqual(timers.count(), 0);
});
