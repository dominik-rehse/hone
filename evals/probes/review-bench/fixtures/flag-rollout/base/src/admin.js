const store = require("./store.js");
const flags = require("./flag.js");
const audit = require("./audit.js");

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
  return store.all().map((one) => flags.describe(one));
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
  remove,
  listing,
  history,
};
