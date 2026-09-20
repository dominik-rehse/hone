const test = require("node:test");
const assert = require("node:assert");
const jobs = require("../../src/jobs.js");

test.beforeEach(() => jobs.resetIds());

test("makes a job with an id of its own", () => {
  const first = jobs.make({ tenantId: "acme", kind: "email" });
  const second = jobs.make({ tenantId: "acme", kind: "email" });
  assert.strictEqual(first.id, "job-1");
  assert.strictEqual(second.id, "job-2");
});

test("keeps the tenant and the payload it was given", () => {
  const job = jobs.make({
    tenantId: " acme ",
    kind: "report",
    payload: { month: "may" },
  });
  assert.strictEqual(job.tenantId, "acme");
  assert.deepStrictEqual(job.payload, { month: "may" });
  assert.ok(job.at > 0);
});

test("refuses a job with no tenant", () => {
  assert.throws(() => jobs.make({ kind: "email" }), TypeError);
  assert.throws(() => jobs.make({ tenantId: "  ", kind: "email" }), TypeError);
});

test("refuses a kind it does not run", () => {
  assert.throws(() => jobs.make({ tenantId: "acme", kind: "dance" }), RangeError);
  assert.strictEqual(jobs.isKind("export"), true);
  assert.strictEqual(jobs.isKind("dance"), false);
});

test("reads a job as one line", () => {
  const job = jobs.make({ tenantId: "acme", kind: "email" });
  assert.strictEqual(jobs.describe(job), "job-1 email for acme");
});
