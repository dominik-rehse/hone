const test = require("node:test");
const assert = require("node:assert");
const metrics = require("../src/metrics.js");
const quota = require("../src/quota.js");

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test.beforeEach(() => {
  quota.stopWindows();
  quota.reset();
  metrics.reset();
});

test.after(() => quota.stopWindows());

test("a tenant starts a window at nothing", () => {
  assert.strictEqual(quota.count("acme"), 0);
  assert.strictEqual(quota.remaining("acme", 5), 5);
});

test("counts what a tenant has put in", () => {
  assert.strictEqual(quota.record("acme"), 1);
  assert.strictEqual(quota.record("acme"), 2);
  assert.strictEqual(quota.count("acme"), 2);
  assert.strictEqual(quota.remaining("acme", 5), 3);
});

test("keeps one tenant's count off another's", () => {
  quota.record("acme");
  quota.record("acme");
  quota.record("mint");
  assert.deepStrictEqual(quota.snapshot(), { acme: 2, mint: 1 });
});

test("never reads below nothing left", () => {
  for (let i = 0; i < 8; i += 1) {
    quota.record("acme");
  }
  assert.strictEqual(quota.remaining("acme", 5), 0);
});

test("a new window starts every tenant from nothing", () => {
  quota.record("acme");
  quota.record("mint");
  quota.resetWindow(1000);
  assert.strictEqual(quota.count("acme"), 0);
  assert.deepStrictEqual(quota.snapshot(), {});
  assert.strictEqual(metrics.get("quota.windows"), 1);
});

test("a window runs out after its minute", () => {
  quota.resetWindow(1000);
  assert.strictEqual(quota.windowIsOver(1000 + quota.WINDOW_MS - 1), false);
  assert.strictEqual(quota.windowIsOver(1000 + quota.WINDOW_MS), true);
});

test("a window that has run its minute out rolls over on its own", () => {
  quota.resetWindow(1000);
  quota.record("acme");
  assert.strictEqual(quota.rollWindow(1000 + quota.WINDOW_MS - 1), 1000);
  assert.strictEqual(quota.count("acme"), 1);
  assert.strictEqual(
    quota.rollWindow(1000 + quota.WINDOW_MS),
    1000 + quota.WINDOW_MS,
  );
  assert.strictEqual(quota.count("acme"), 0);
});

test("the window timer leaves one timer behind it, and stops once", () => {
  const handle = quota.startWindows(1000);
  assert.notStrictEqual(quota.startWindows(1000), handle);
  assert.strictEqual(quota.stopWindows(), true);
  assert.strictEqual(quota.stopWindows(), false);
});

test("the window timer opens new windows while it runs", async () => {
  quota.record("acme");
  quota.startWindows(5);
  await sleep(40);
  quota.stopWindows();
  assert.ok(metrics.get("quota.windows") > 0, "a window opened while it ran");
  assert.strictEqual(quota.count("acme"), 0);
});
