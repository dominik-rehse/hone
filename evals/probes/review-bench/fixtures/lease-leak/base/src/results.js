// What became of each job the last time it ran.
const written = new Map();
// What it wrote down the last time it got through, which need not be the same
// run.
const gotThrough = new Map();

function record(jobId, result) {
  written.set(jobId, result);
  if (result.status === "ok") {
    gotThrough.set(jobId, result);
  }
  return result;
}

function find(jobId) {
  return written.get(jobId) ?? null;
}

// What the job's last run that got through wrote down, or null when no run of
// it ever got through.
function lastSuccess(jobId) {
  return gotThrough.get(jobId) ?? null;
}

function all() {
  return [...written.values()];
}

function count() {
  return written.size;
}

function forget(jobId) {
  gotThrough.delete(jobId);
  return written.delete(jobId);
}

function reset() {
  written.clear();
  gotThrough.clear();
}

module.exports = { record, find, lastSuccess, all, count, forget, reset };
