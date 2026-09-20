// The flag list: one flag per key, held for the life of the process.

const flags = new Map();

function put(flag) {
  flags.set(flag.key, flag);
  return flag;
}

function get(key) {
  return flags.has(key) ? flags.get(key) : null;
}

function has(key) {
  return flags.has(key);
}

function remove(key) {
  return flags.delete(key);
}

function keys() {
  return [...flags.keys()].sort();
}

function all() {
  return keys().map((key) => flags.get(key));
}

function size() {
  return flags.size;
}

function reset() {
  flags.clear();
}

module.exports = { put, get, has, remove, keys, all, size, reset };
