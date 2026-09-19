// What became of each job the last time it ran.
const written = new Map();

function record(jobId, result) {
  written.set(jobId, result);
  return result;
}

function find(jobId) {
  return written.get(jobId) ?? null;
}

function all() {
  return [...written.values()];
}

function count() {
  return written.size;
}

function forget(jobId) {
  return written.delete(jobId);
}

function reset() {
  written.clear();
}

module.exports = { record, find, all, count, forget, reset };
