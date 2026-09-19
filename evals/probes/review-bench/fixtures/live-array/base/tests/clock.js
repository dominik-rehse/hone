// A clock for the store that moves one minute on every reading, so a test
// reads back the times it expects. Not a test file, so the suite skips it.
const START = 1_700_000_000_000;
const MINUTE = 60 * 1000;

function minuteClock(start = START) {
  let t = start - MINUTE;
  return () => {
    t += MINUTE;
    return t;
  };
}

module.exports = { minuteClock, START, MINUTE };
