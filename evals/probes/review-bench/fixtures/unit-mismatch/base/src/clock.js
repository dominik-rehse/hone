// Every time this service reads comes from here, so a test can hold it still.
let source = () => Date.now();

function now() {
  return source();
}

// The instant `ms` milliseconds from now.
function after(ms) {
  return now() + ms;
}

function setSource(fn) {
  source = fn;
}

function useRealTime() {
  source = () => Date.now();
}

module.exports = { now, after, setSource, useRealTime };
