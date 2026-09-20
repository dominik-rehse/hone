const test = require("node:test");
const assert = require("node:assert");
const flag = require("../../src/flag.js");

test("fills in what the caller left out", () => {
  const one = flag.makeFlag({ key: "checkout-v2" });
  assert.strictEqual(one.description, "");
  assert.strictEqual(one.enabled, false);
  assert.strictEqual(one.owner, "unassigned");
  assert.deepStrictEqual(one.tags, []);
});

test("takes the tags it was given and not the array", () => {
  const tags = ["billing"];
  const one = flag.makeFlag({ key: "checkout-v2", tags });
  tags.push("later");
  assert.deepStrictEqual(one.tags, ["billing"]);
});

test("refuses a flag with no key", () => {
  assert.throws(() => flag.makeFlag({ description: "no key" }), TypeError);
  assert.throws(() => flag.makeFlag({ key: "   " }), TypeError);
});

test("reads a flag as one line", () => {
  const one = flag.makeFlag({ key: "new-nav", enabled: true, owner: "web" });
  assert.strictEqual(flag.describe(one), "new-nav on (web)");
});

test("knows the tags a flag carries", () => {
  const one = flag.makeFlag({ key: "new-nav", tags: ["web", "archived"] });
  assert.strictEqual(flag.hasTag(one, "archived"), true);
  assert.strictEqual(flag.hasTag(one, "billing"), false);
});
