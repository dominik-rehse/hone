const store = require("./store.js");
const flag = require("./flag.js");

// Whether one flag is on for this caller.
function evaluate(one, ctx = {}) {
  if (one === null || one === undefined) {
    return false;
  }
  if (flag.hasTag(one, "archived")) {
    return false;
  }
  return one.enabled === true;
}

// Whether the flag under this key is on. A key the list does not carry is off.
function isOn(key, ctx = {}) {
  return evaluate(store.get(key), ctx);
}

// Every key that is on for this caller, in order.
function onFor(ctx = {}) {
  return store
    .all()
    .filter((one) => evaluate(one, ctx))
    .map((one) => one.key);
}

// What the client library asks for at the start of a session.
function snapshotFor(ctx = {}) {
  const on = onFor(ctx);
  return Object.fromEntries(store.keys().map((key) => [key, on.includes(key)]));
}

module.exports = { evaluate, isOn, onFor, snapshotFor };
