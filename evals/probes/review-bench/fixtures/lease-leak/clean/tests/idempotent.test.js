const test = require("node:test");
const assert = require("node:assert");
const clock = require("../src/clock.js");
const jobs = require("../src/jobs.js");
const leases = require("../src/leases.js");
const metrics = require("../src/metrics.js");
const results = require("../src/results.js");
const state = require("../src/state.js");
const { runJob, runAll } = require("../src/runner.js");

const t0 = 1_700_000_000_000;
let at = t0;

function seed() {
  at = t0;
  clock.setSource(() => at);
  jobs.reset();
  leases.reset();
  metrics.reset();
  results.reset();
  state.reset();
}

const step = (name, run) => ({ name, run });
const counting = (seen) => [step("pull", () => seen.push("pull"))];

test("runs a job nothing has been written down about", () => {
  seed();
  const seen = [];
  const job = jobs.define({ id: "nightly", steps: counting(seen) });
  assert.strictEqual(runJob(job).status, "ok");
  assert.deepStrictEqual(seen, ["pull"]);
});

test("leaves a job that has already been done alone", () => {
  seed();
  const seen = [];
  const job = jobs.define({ id: "nightly", steps: counting(seen) });
  runJob(job);
  const second = runJob(job);
  assert.strictEqual(second.status, "skipped");
  assert.deepStrictEqual(seen, ["pull"]);
});

test("hands back what the run that did the work wrote down", () => {
  seed();
  const job = jobs.define({ id: "nightly", steps: counting([]) });
  const first = runJob(job);
  at = t0 + 90_000;
  const second = runJob(job);
  assert.strictEqual(second.jobId, first.jobId);
  assert.strictEqual(second.startedAt, first.startedAt);
  assert.deepStrictEqual(second.steps, first.steps);
});

test("counts the jobs it left alone", () => {
  seed();
  const job = jobs.define({ id: "nightly", steps: counting([]) });
  runJob(job);
  runJob(job);
  assert.strictEqual(metrics.count("skipped"), 1);
  assert.strictEqual(metrics.count("run"), 1);
});

test("the dashboard has a counter for it", () => {
  seed();
  assert.ok(metrics.known().includes("skipped"));
  assert.strictEqual(metrics.count("skipped"), 0);
});

test("runs a job again whose last run did not get through", () => {
  seed();
  let thrown = true;
  const job = jobs.define({
    id: "nightly",
    steps: [step("pull", () => {
      if (thrown) {
        thrown = false;
        throw new Error("the supplier is down");
      }
    })],
  });
  assert.strictEqual(runJob(job).status, "failed");
  assert.strictEqual(runJob(job).status, "ok");
});

test("leaves a job alone whose run got through, after a later one did not", () => {
  seed();
  const seen = [];
  jobs.define({ id: "nightly", version: 1, steps: counting(seen) });
  runJob(jobs.get("nightly"));
  jobs.define({
    id: "nightly",
    version: 2,
    steps: [step("pull", () => {
      throw new Error("the supplier is down");
    })],
  });
  assert.strictEqual(runJob(jobs.get("nightly")).status, "failed");
  jobs.define({ id: "nightly", version: 1, steps: counting(seen) });
  assert.strictEqual(runJob(jobs.get("nightly")).status, "skipped");
  assert.deepStrictEqual(seen, ["pull"]);
});

test("runs a job again once nothing is written down about it any more", () => {
  seed();
  const seen = [];
  const job = jobs.define({ id: "nightly", steps: counting(seen) });
  runJob(job);
  results.forget("nightly");
  assert.strictEqual(runJob(job).status, "ok");
  assert.deepStrictEqual(seen, ["pull", "pull"]);
});

test("runs a job again once its definition has moved on", () => {
  seed();
  const seen = [];
  jobs.define({ id: "nightly", version: 1, steps: counting(seen) });
  runJob(jobs.get("nightly"));
  jobs.define({ id: "nightly", version: 2, steps: counting(seen) });
  assert.strictEqual(runJob(jobs.get("nightly")).status, "ok");
  assert.deepStrictEqual(seen, ["pull", "pull"]);
});

test("leaves a job alone where the scheduler went back to an older definition", () => {
  seed();
  const seen = [];
  jobs.define({ id: "nightly", version: 2, steps: counting(seen) });
  runJob(jobs.get("nightly"));
  jobs.define({ id: "nightly", version: 1, steps: counting(seen) });
  assert.strictEqual(runJob(jobs.get("nightly")).status, "skipped");
  assert.deepStrictEqual(seen, ["pull"]);
});

test("walks a list and says how many of them were already done", () => {
  seed();
  const seen = [];
  const nightly = jobs.define({ id: "nightly", leaseKey: "warehouse", steps: counting(seen) });
  const weekly = jobs.define({ id: "weekly", leaseKey: "ledger", steps: counting(seen) });
  runJob(nightly);
  const out = runAll([nightly, weekly]);
  assert.strictEqual(out.skipped, 1);
  assert.deepStrictEqual(out.results.map((r) => r.status), ["skipped", "ok"]);
  assert.deepStrictEqual(seen, ["pull", "pull"]);
});
