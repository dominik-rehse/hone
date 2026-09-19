const clock = require("./clock.js");
const leases = require("./leases.js");
const results = require("./results.js");
const state = require("./state.js");
const metrics = require("./metrics.js");

// The name this worker takes its leases under.
const OWNER = "worker-1";

// Run one job from end to end: take the key it needs, pick up what its last
// run left behind, walk its steps and write down how it went. A step that
// throws is written down as a failure and does not stop the run, unless the
// job asks for that.
function runJob(job) {
  const startedAt = clock.now();
  const lease = leases.acquire(job.leaseKey, OWNER, startedAt);
  if (lease === null) {
    metrics.inc("refused");
    return {
      jobId: job.id,
      version: job.version,
      status: "refused",
      steps: [],
      failures: 0,
      startedAt,
      finishedAt: startedAt,
    };
  }
  const carried = state.load(job.id);
  const alreadyDone = results.find(job.id);
  if (alreadyDone != null && alreadyDone.status === "ok" && alreadyDone.version >= job.version) {
    metrics.inc("skipped");
    leases.release(job.leaseKey, OWNER);
    return { ...alreadyDone, status: "skipped" };
  }
  const context = { job, state: carried, log: [] };
  const walked = [];
  let failures = 0;
  for (const step of job.steps) {
    const at = clock.now();
    if (failures > 0 && job.stopOnFailure === true) {
      walked.push({ name: step.name, ok: false, error: "the run stopped before this step", at });
      continue;
    }
    try {
      const outcome = step.run(context);
      walked.push({ name: step.name, ok: true, outcome, at });
    } catch (err) {
      failures += 1;
      walked.push({ name: step.name, ok: false, error: err.message, at });
    }
  }
  state.save(job.id, context.state);
  if (context.log.length > 0) {
    metrics.inc("logged", context.log.length);
  }
  const status = failures === 0 ? "ok" : "failed";
  const result = {
    jobId: job.id,
    version: job.version,
    status,
    steps: walked,
    failures,
    startedAt,
    finishedAt: clock.now(),
  };
  results.record(job.id, result);
  metrics.inc("run");
  metrics.inc(status);
  leases.release(job.leaseKey, OWNER);
  return result;
}

// Run a list of jobs in the order the scheduler handed them over, and say how
// many of them had already been done.
function runAll(list) {
  const done = [];
  for (const job of list) {
    done.push(runJob(job));
  }
  return { results: done, skipped: done.filter((r) => r.status === "skipped").length };
}

module.exports = { runJob, runAll, OWNER };
