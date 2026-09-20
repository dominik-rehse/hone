// The clock the rest of the service reads. A test pins it to a fixed number
// so that an audit entry comes out the same on every run.
let reading = () => Date.now();

function now() {
  return reading();
}

function setClock(fn) {
  reading = fn;
}

function useRealClock() {
  reading = () => Date.now();
}

module.exports = { now, setClock, useRealClock };
