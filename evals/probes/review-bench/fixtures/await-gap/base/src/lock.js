// Tasks handed in under one key run one after another. Two keys do not wait
// for each other.

const chains = new Map();
const ignore = () => undefined;

function withLock(key, task) {
  const before = chains.get(key) ?? Promise.resolve();
  const run = before.then(task, task);
  const done = run.then(ignore, ignore).then(() => {
    if (chains.get(key) === done) {
      chains.delete(key);
    }
  });
  chains.set(key, done);
  return run;
}

// Has the key a task in hand or waiting?
function isBusy(key) {
  return chains.has(key);
}

function busyKeys() {
  return [...chains.keys()];
}

function reset() {
  chains.clear();
}

module.exports = { withLock, isBusy, busyKeys, reset };
