const defined = new Map();

// A job as the scheduler hands it over: an id, the key it holds while it runs,
// the version of the definition it was cut from, and its steps in order.
function define({ id, leaseKey, version = 1, steps, stopOnFailure = false }) {
  const job = { id, leaseKey: leaseKey ?? id, version, steps, stopOnFailure };
  defined.set(id, job);
  return job;
}

function get(id) {
  return defined.get(id) ?? null;
}

function all() {
  return [...defined.values()];
}

function reset() {
  defined.clear();
}

module.exports = { define, get, all, reset };
