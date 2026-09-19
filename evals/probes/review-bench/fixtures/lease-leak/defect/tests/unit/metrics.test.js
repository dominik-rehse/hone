const test = require("node:test");
const assert = require("node:assert");
const metrics = require("../../src/metrics.js");

test("starts every counter at nothing", () => {
  metrics.reset();
  assert.deepStrictEqual(metrics.snapshot(), {
    run: 0,
    ok: 0,
    failed: 0,
    refused: 0,
    skipped: 0,
    logged: 0,
  });
});

test("counts one more, and as many more as asked", () => {
  metrics.reset();
  assert.strictEqual(metrics.inc("run"), 1);
  assert.strictEqual(metrics.inc("run"), 2);
  assert.strictEqual(metrics.inc("logged", 5), 5);
  assert.strictEqual(metrics.count("run"), 2);
});

test("does not count a name the dashboard does not have", () => {
  metrics.reset();
  assert.strictEqual(metrics.inc("nonsense"), null);
  assert.strictEqual(metrics.count("nonsense"), 0);
  assert.ok(!metrics.known().includes("nonsense"));
});
