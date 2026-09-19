// The counters the operations dashboard reads. A name that is not one of
// these is not counted, so a typo in a call site cannot invent a counter.
const NAMES = ["run", "ok", "failed", "refused", "logged"];

const counters = {};

function reset() {
  for (const name of NAMES) {
    counters[name] = 0;
  }
}

reset();

// Count one more. Null for a name the dashboard does not have.
function inc(name, by = 1) {
  if (!Object.prototype.hasOwnProperty.call(counters, name)) {
    return null;
  }
  counters[name] += by;
  return counters[name];
}

function count(name) {
  return counters[name] ?? 0;
}

function known() {
  return [...NAMES];
}

function snapshot() {
  return { ...counters };
}

module.exports = { inc, count, known, snapshot, reset, NAMES };
