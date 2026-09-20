const queue = require("./queue.js");
const metrics = require("./metrics.js");

const handlers = new Map();

function handle(kind, fn) {
  handlers.set(kind, fn);
  return kind;
}

// The next `n` jobs to run, taken off the queue.
function nextBatch(n) {
  const pending = queue.all();
  const batch = pending.slice(0, n);
  queue.replace(pending.slice(n));
  return batch;
}

// Run one job. A job whose kind has no handler is counted and let go, because
// a handler is registered at boot and a missing one is a deploy problem.
function run(job) {
  const fn = handlers.get(job.kind);
  if (fn === undefined) {
    metrics.inc("dispatch.unhandled");
    return { id: job.id, ok: false, reason: "no-handler" };
  }
  try {
    fn(job);
  } catch (err) {
    metrics.inc("dispatch.failed");
    return { id: job.id, ok: false, reason: "threw" };
  }
  metrics.inc("dispatch.ran");
  return { id: job.id, ok: true };
}

// Run a batch and say how it went.
function runBatch(n) {
  const results = nextBatch(n).map((job) => run(job));
  return {
    ran: results.filter((r) => r.ok).length,
    refused: results.filter((r) => !r.ok).length,
  };
}

function pending() {
  return queue.size();
}

function reset() {
  handlers.clear();
}

module.exports = { handle, nextBatch, run, runBatch, pending, reset };
