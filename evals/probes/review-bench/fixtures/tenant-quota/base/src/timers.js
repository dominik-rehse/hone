// The timers this process has running.

const running = new Set();

function register(timer) {
  running.add(timer);
  return timer;
}

function forget(timer) {
  return running.delete(timer);
}

function count() {
  return running.size;
}

// Put the timers out and say how many there were.
function shutdown() {
  const n = running.size;
  for (const timer of running) {
    clearInterval(timer);
  }
  running.clear();
  return n;
}

module.exports = { register, forget, count, shutdown };
