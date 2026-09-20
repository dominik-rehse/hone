// The pending jobs, oldest first. The queue is bounded because the process
// holds it in memory and a runaway tenant would otherwise take the box down.

const DEFAULT_CAPACITY = 64;

let capacity = DEFAULT_CAPACITY;
const items = [];

function setCapacity(n) {
  capacity = n;
  return capacity;
}

function getCapacity() {
  return capacity;
}

function push(job) {
  if (items.length >= capacity) {
    return false;
  }
  items.push(job);
  return true;
}

function take() {
  return items.length === 0 ? null : items.shift();
}

function peek() {
  return items.length === 0 ? null : items[0];
}

function all() {
  return [...items];
}

// Put a whole list in place of the one that is there. The caller has just
// worked out what should be pending.
function replace(next) {
  items.length = 0;
  for (const job of next) {
    items.push(job);
  }
  return items.length;
}

function isFull() {
  return items.length >= capacity;
}

function size() {
  return items.length;
}

function clear() {
  items.length = 0;
  capacity = DEFAULT_CAPACITY;
}

module.exports = {
  DEFAULT_CAPACITY,
  setCapacity,
  getCapacity,
  push,
  take,
  peek,
  all,
  replace,
  isFull,
  size,
  clear,
};
