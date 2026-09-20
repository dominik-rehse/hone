// A flag as the store keeps it, and the two readings of one the rest of the
// service asks for.

const DEFAULTS = { description: "", enabled: false, owner: "unassigned" };

function makeFlag(input) {
  if (typeof input !== "object" || input === null) {
    throw new TypeError("a flag is made from an object");
  }
  if (typeof input.key !== "string" || input.key.trim() === "") {
    throw new TypeError("a flag needs a key");
  }
  return {
    ...DEFAULTS,
    ...input,
    key: input.key.trim(),
    enabled: input.enabled === true,
    tags: [...(input.tags ?? [])],
  };
}

function view(flag) {
  return { ...flag };
}

function describe(flag) {
  return `${flag.key} ${flag.enabled ? "on" : "off"} (${flag.owner})`;
}

function hasTag(flag, tag) {
  return flag.tags.includes(tag);
}

module.exports = { makeFlag, view, describe, hasTag };
