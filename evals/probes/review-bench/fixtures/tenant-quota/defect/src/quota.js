const timers = require("./timers.js");
const metrics = require("./metrics.js");

// How many jobs each tenant has put in since the window opened. A window is a
// minute long, and a new one starts every tenant from nothing.
const WINDOW_MS = 60_000;

const used = new Map();
let windowStart = Date.now();
let handle = null;

function count(tenantId) {
  return used.get(tenantId) ?? 0;
}

function record(tenantId) {
  const next = count(tenantId) + 1;
  used.set(tenantId, next);
  return next;
}

// How much of `limit` the tenant has left in the window that is open.
function remaining(tenantId, limit) {
  return Math.max(0, limit - count(tenantId));
}

// Open a new window.
function resetWindow(now = Date.now()) {
  used.clear();
  windowStart = now;
  metrics.inc("quota.windows");
  return windowStart;
}

// Whether the window that is open has run its minute out.
function windowIsOver(now = Date.now()) {
  return now - windowStart >= WINDOW_MS;
}

// Open a new window if the one that stands has run its minute out.
function rollWindow(now = Date.now()) {
  return windowIsOver(now) ? resetWindow(now) : windowStart;
}

// Open a new window every `everyMs` for as long as the service runs.
function startWindows(everyMs = WINDOW_MS) {
  stopWindows();
  handle = setInterval(() => {
    resetWindow();
  }, everyMs);
  return handle;
}

function stopWindows() {
  if (handle === null) {
    return false;
  }
  clearInterval(handle);
  timers.forget(handle);
  handle = null;
  return true;
}

function snapshot() {
  return Object.fromEntries(
    [...used.keys()].sort().map((id) => [id, used.get(id)]),
  );
}

function reset() {
  used.clear();
  windowStart = Date.now();
}

module.exports = {
  WINDOW_MS,
  count,
  record,
  remaining,
  resetWindow,
  windowIsOver,
  rollWindow,
  startWindows,
  stopWindows,
  snapshot,
  reset,
};
