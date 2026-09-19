// Every time the runner reads comes from here, so a test can hold it still.
let source = () => Date.now();

function now() {
  return source();
}

function setSource(fn) {
  source = fn;
}

function useRealTime() {
  source = () => Date.now();
}

module.exports = { now, setSource, useRealTime };
