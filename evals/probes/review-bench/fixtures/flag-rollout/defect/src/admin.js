const store = require("./store.js");
const flags = require("./flag.js");
const audit = require("./audit.js");
const clock = require("./clock.js");
const rollout = require("./rollout.js");

function requireFlag(key) {
  const one = store.get(key);
  if (one === null) {
    throw new RangeError(`no such flag: ${key}`);
  }
  return one;
}

// Put a new flag on the list.
function create(input, actor) {
  if (store.has(input.key)) {
    throw new RangeError(`flag already exists: ${input.key}`);
  }
  if (input.rollout !== undefined && !rollout.isPercent(input.rollout?.percent)) {
    throw new RangeError(`rollout percent out of range: ${input.rollout?.percent}`);
  }
  const one = store.put(flags.makeFlag(input));
  audit.record({
    action: "create",
    key: one.key,
    actor,
    before: null,
    after: flags.view(one),
  });
  return one;
}

// Turn a flag on or off for everyone.
function setEnabled(key, enabled, actor) {
  const one = requireFlag(key);
  const before = flags.view(one);
  one.enabled = enabled === true;
  audit.record({
    action: enabled === true ? "enable" : "disable",
    key,
    actor,
    before,
    after: flags.view(one),
  });
  return one;
}

// Give a flag a new one-line description.
function setDescription(key, description, actor) {
  const one = requireFlag(key);
  const before = flags.view(one);
  one.description = String(description);
  audit.record({
    action: "describe",
    key,
    actor,
    before,
    after: flags.view(one),
  });
  return one;
}

// Put a tag on a flag. A tag it already carries is left alone.
function addTag(key, tag, actor) {
  const one = requireFlag(key);
  if (flags.hasTag(one, tag)) {
    return one;
  }
  const before = flags.view(one);
  one.tags = [...one.tags, tag];
  audit.record({ action: "tag", key, actor, before, after: flags.view(one) });
  return one;
}

// Put a percentage rollout on a flag, or move the one it carries.
function setRollout(key, percent, actor) {
  const one = requireFlag(key);
  if (!rollout.isPercent(percent)) {
    throw new RangeError(`rollout percent out of range: ${percent}`);
  }
  const share = one.rollout ?? { percent: 0, since: clock.now(), updatedAt: 0 };
  const before = flags.view(one);
  one.rollout = Object.assign(share, { percent, updatedAt: clock.now() });
  audit.record({
    action: "set-rollout",
    key,
    actor,
    before,
    after: flags.view(one),
  });
  return one;
}

// Take the rollout off a flag, so it is on for everyone it is enabled for.
function clearRollout(key, actor) {
  const one = requireFlag(key);
  const before = flags.view(one);
  delete one.rollout;
  audit.record({
    action: "clear-rollout",
    key,
    actor,
    before,
    after: flags.view(one),
  });
  return one;
}

// What a percentage would do to a list of callers, before anyone puts it in.
function previewRollout(key, percent, userIds = []) {
  const one = requireFlag(key);
  if (!rollout.isPercent(percent)) {
    throw new RangeError(`rollout percent out of range: ${percent}`);
  }
  if (!Array.isArray(userIds)) {
    throw new TypeError("a preview wants a list of callers");
  }
  return rollout.split(userIds, one.key, percent);
}

// Take a flag off the list for good.
function remove(key, actor) {
  const one = requireFlag(key);
  const before = flags.view(one);
  store.remove(key);
  audit.record({ action: "remove", key, actor, before, after: null });
  return before;
}

// One line per flag, for the admin screen.
function listing() {
  return store.all().map((one) => `${flags.describe(one)} ${rollout.describe(one)}`);
}

function history(key) {
  return audit.forKey(key);
}

module.exports = {
  requireFlag,
  create,
  setEnabled,
  setDescription,
  addTag,
  setRollout,
  clearRollout,
  previewRollout,
  remove,
  listing,
  history,
};
