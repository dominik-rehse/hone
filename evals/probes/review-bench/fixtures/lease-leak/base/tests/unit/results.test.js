const test = require("node:test");
const assert = require("node:assert");
const results = require("../../src/results.js");

const result = (jobId, status) => ({ jobId, version: 1, status });

test("writes down what became of a job", () => {
  results.reset();
  results.record("nightly", result("nightly", "ok"));
  assert.strictEqual(results.find("nightly").status, "ok");
});

test("has nothing for a job that has not run", () => {
  results.reset();
  assert.strictEqual(results.find("nightly"), null);
});

test("keeps the last word on a job", () => {
  results.reset();
  results.record("nightly", result("nightly", "failed"));
  results.record("nightly", result("nightly", "ok"));
  assert.strictEqual(results.find("nightly").status, "ok");
  assert.strictEqual(results.count(), 1);
});

test("forgets one job and leaves the rest", () => {
  results.reset();
  results.record("nightly", result("nightly", "ok"));
  results.record("weekly", result("weekly", "ok"));
  assert.strictEqual(results.forget("nightly"), true);
  assert.strictEqual(results.forget("nightly"), false);
  assert.deepStrictEqual(results.all().map((r) => r.jobId), ["weekly"]);
});
