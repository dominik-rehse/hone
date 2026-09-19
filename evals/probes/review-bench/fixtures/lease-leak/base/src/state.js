// What a job left behind for its next run. A copy goes in and a copy comes
// out, so a step cannot reach into the box.
const kept = new Map();

function load(jobId) {
  return { ...(kept.get(jobId) ?? {}) };
}

function save(jobId, value) {
  kept.set(jobId, { ...value });
  return load(jobId);
}

function forget(jobId) {
  return kept.delete(jobId);
}

function reset() {
  kept.clear();
}

module.exports = { load, save, forget, reset };
