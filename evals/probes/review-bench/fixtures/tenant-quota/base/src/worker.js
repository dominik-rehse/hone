const timers = require("./timers.js");
const dispatch = require("./dispatch.js");
const metrics = require("./metrics.js");

const DEFAULT_EVERY_MS = 50;
const DEFAULT_BATCH = 4;

let handle = null;

// Take a batch off the queue every `everyMs` for as long as the service runs.
function start(everyMs = DEFAULT_EVERY_MS, batch = DEFAULT_BATCH) {
  if (handle !== null) {
    return handle;
  }
  handle = timers.register(
    setInterval(() => {
      tick(batch);
    }, everyMs),
  );
  return handle;
}

// One pass over the queue, by hand or from the timer.
function tick(batch = DEFAULT_BATCH) {
  const result = dispatch.runBatch(batch);
  metrics.inc("worker.ticks");
  return result;
}

function stop() {
  if (handle === null) {
    return false;
  }
  clearInterval(handle);
  timers.forget(handle);
  handle = null;
  return true;
}

function isRunning() {
  return handle !== null;
}

module.exports = { DEFAULT_EVERY_MS, DEFAULT_BATCH, start, tick, stop, isRunning };
