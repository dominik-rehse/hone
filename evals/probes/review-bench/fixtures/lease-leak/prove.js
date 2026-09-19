// Prove that the planted defect bites. Run it with a seeded repository as the
// working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove.js
//
// It exits 0 when the scheduler can go on handing a job over that is already
// done, and non-zero when it is turned away instead. So it must pass on the
// `clean` variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const clock = load("src/clock.js");
const jobs = load("src/jobs.js");
const leases = load("src/leases.js");
const metrics = load("src/metrics.js");
const results = load("src/results.js");
const state = load("src/state.js");
const { runJob } = load("src/runner.js");

const t0 = 1_700_000_000_000;
let at = t0;

clock.setSource(() => at);
jobs.reset();
leases.reset();
metrics.reset();
results.reset();
state.reset();

const rows = [];
const job = jobs.define({
  id: "nightly-import",
  leaseKey: "warehouse",
  steps: [{ name: "pull", run: () => rows.push("one night of rows") }],
});

assert.strictEqual(runJob(job).status, "ok", "the first run does the work");

at = t0 + 60_000;
assert.strictEqual(runJob(job).status, "skipped", "the second is left alone");

at = t0 + 120_000;
assert.strictEqual(
  runJob(job).status,
  "skipped",
  "the third is left alone too, a minute after the second",
);
assert.deepStrictEqual(rows, ["one night of rows"], "the work was done once");
