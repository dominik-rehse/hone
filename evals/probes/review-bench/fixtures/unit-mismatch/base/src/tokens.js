// Session ids. The real deployment reads them out of the random source; the
// counter keeps a test's output the same twice running.
let counter = 0;

function next() {
  counter += 1;
  return `s-${counter}`;
}

function reset() {
  counter = 0;
}

module.exports = { next, reset };
