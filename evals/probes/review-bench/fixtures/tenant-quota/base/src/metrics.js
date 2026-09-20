const timers = require("./timers.js");

// Counters, by name. Nothing here is ever read back in anger; the flush sends
// them on and the tests read them.
const counters = new Map();

function inc(name, by = 1) {
  const next = (counters.get(name) ?? 0) + by;
  counters.set(name, next);
  return next;
}

function get(name) {
  return counters.get(name) ?? 0;
}

function names() {
  return [...counters.keys()].sort();
}

function snapshot() {
  return Object.fromEntries(names().map((name) => [name, counters.get(name)]));
}

// Send the counters on every `everyMs`.
function startFlush(everyMs, sink) {
  return timers.register(
    setInterval(() => {
      sink(snapshot());
    }, everyMs),
  );
}

function reset() {
  counters.clear();
}

module.exports = { inc, get, names, snapshot, startFlush, reset };
