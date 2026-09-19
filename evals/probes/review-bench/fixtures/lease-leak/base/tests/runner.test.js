const test = require("node:test");
const assert = require("node:assert");
const clock = require("../src/clock.js");
const jobs = require("../src/jobs.js");
const leases = require("../src/leases.js");
const metrics = require("../src/metrics.js");
const results = require("../src/results.js");
const state = require("../src/state.js");
const { runJob, OWNER } = require("../src/runner.js");

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

test("walks the steps of a job in order", () => {
  seed();
  const seen = [];
  const job = jobs.define({
    id: "nightly",
    steps: [
      step("pull", () => seen.push("pull")),
      step("tidy", () => seen.push("tidy")),
    ],
  });
  const result = runJob(job);
  assert.deepStrictEqual(seen, ["pull", "tidy"]);
  assert.strictEqual(result.status, "ok");
  assert.deepStrictEqual(result.steps.map((s) => s.name), ["pull", "tidy"]);
});

test("writes down what the last run left behind", () => {
  seed();
  const job = jobs.define({
    id: "nightly",
    steps: [step("count", (context) => {
      context.state.cursor = (context.state.cursor ?? 0) + 1;
    })],
  });
  state.save("nightly", { cursor: 4 });
  runJob(job);
  assert.deepStrictEqual(state.load("nightly"), { cursor: 5 });
});

test("writes a step that throws down as a failure and carries on", () => {
  seed();
  const seen = [];
  const job = jobs.define({
    id: "nightly",
    steps: [
      step("pull", () => {
        throw new Error("the supplier is down");
      }),
      step("tidy", () => seen.push("tidy")),
    ],
  });
  const result = runJob(job);
  assert.strictEqual(result.status, "failed");
  assert.strictEqual(result.failures, 1);
  assert.strictEqual(result.steps[0].error, "the supplier is down");
  assert.deepStrictEqual(seen, ["tidy"]);
});

test("leaves the rest of the steps where the job asks for it", () => {
  seed();
  const seen = [];
  const job = jobs.define({
    id: "nightly",
    stopOnFailure: true,
    steps: [
      step("pull", () => {
        throw new Error("the supplier is down");
      }),
      step("tidy", () => seen.push("tidy")),
    ],
  });
  const result = runJob(job);
  assert.deepStrictEqual(seen, []);
  assert.strictEqual(result.steps[1].ok, false);
});

test("writes down how the run went", () => {
  seed();
  const job = jobs.define({ id: "nightly", steps: [step("pull", () => 7)] });
  at = t0 + 250;
  const result = runJob(job);
  assert.strictEqual(results.find("nightly"), result);
  assert.strictEqual(result.startedAt, t0 + 250);
  assert.strictEqual(result.version, 1);
});

test("puts the key back when it is done", () => {
  seed();
  const job = jobs.define({ id: "nightly", leaseKey: "warehouse", steps: [] });
  runJob(job);
  assert.strictEqual(leases.isHeld("warehouse", at), false);
  assert.notStrictEqual(leases.acquire("warehouse", "worker-2", at), null);
});

test("turns a job away while another worker holds its key", () => {
  seed();
  const seen = [];
  const job = jobs.define({
    id: "nightly",
    leaseKey: "warehouse",
    steps: [step("pull", () => seen.push("pull"))],
  });
  leases.acquire("warehouse", "worker-2", at);
  const result = runJob(job);
  assert.strictEqual(result.status, "refused");
  assert.deepStrictEqual(seen, []);
  assert.strictEqual(results.find("nightly"), null);
  assert.strictEqual(metrics.count("refused"), 1);
});

test("counts the runs the dashboard shows", () => {
  seed();
  const good = jobs.define({ id: "nightly", steps: [step("pull", () => 1)] });
  const bad = jobs.define({
    id: "weekly",
    steps: [step("pull", () => {
      throw new Error("no");
    })],
  });
  runJob(good);
  runJob(bad);
  assert.strictEqual(metrics.count("run"), 2);
  assert.strictEqual(metrics.count("ok"), 1);
  assert.strictEqual(metrics.count("failed"), 1);
});

test("counts what the steps logged", () => {
  seed();
  const job = jobs.define({
    id: "nightly",
    steps: [step("pull", (context) => context.log.push("two rows", "one row"))],
  });
  runJob(job);
  assert.strictEqual(metrics.count("logged"), 2);
  assert.strictEqual(OWNER, "worker-1");
});
