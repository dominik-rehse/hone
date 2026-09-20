const store = require("./store.js");
const flag = require("./flag.js");
const rollout = require("./rollout.js");

// Whether one flag is on for this caller.
function evaluate(one, ctx = {}) {
  if (one === null || one === undefined) {
    return false;
  }
  if (flag.hasTag(one, "archived")) {
    return false;
  }
  if (one.enabled !== true) {
    return false;
  }
  const share = rollout.of(one);
  if (share === null) {
    return true;
  }
  return rollout.inRollout(ctx.userId, one.key, share.percent);
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

// What the debug endpoint answers for one caller and one flag.
function explain(key, ctx = {}) {
  const one = store.get(key);
  if (one === null) {
    return { key, on: false, reason: "no such flag" };
  }
  if (flag.hasTag(one, "archived")) {
    return { key, on: false, reason: "archived" };
  }
  if (one.enabled !== true) {
    return { key, on: false, reason: "disabled" };
  }
  const share = rollout.of(one);
  if (share === null) {
    return { key, on: true, reason: "no rollout" };
  }
  const on = rollout.inRollout(ctx.userId, one.key, share.percent);
  if (share.percent >= 100) {
    return { key, on, reason: "rollout at 100%" };
  }
  if (typeof ctx.userId !== "string" || ctx.userId === "") {
    return { key, on, reason: "no caller id" };
  }
  return {
    key,
    on,
    reason: `rollout at ${share.percent}%`,
    bucket: rollout.bucketFor(ctx.userId, key),
  };
}

module.exports = { evaluate, isOn, onFor, snapshotFor, explain };
