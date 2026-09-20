const clock = require("./clock.js");

// Who changed what, oldest first. The admin screen reads it and nothing else
// writes to it.
const entries = [];

function record(entry) {
  const stored = { at: clock.now(), ...entry };
  entries.push(stored);
  return stored;
}

function all() {
  return [...entries];
}

function last() {
  return entries.length === 0 ? null : entries[entries.length - 1];
}

function forKey(key) {
  return entries.filter((entry) => entry.key === key);
}

function byActor(actor) {
  return entries.filter((entry) => entry.actor === actor);
}

function count() {
  return entries.length;
}

function clear() {
  entries.length = 0;
}

module.exports = { record, all, last, forKey, byActor, count, clear };
