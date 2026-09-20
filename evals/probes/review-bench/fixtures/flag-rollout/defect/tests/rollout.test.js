const test = require("node:test");
const assert = require("node:assert");
const rollout = require("../src/rollout.js");

// The five accounts the team keeps for trying a flag out before it goes wide.
const TEAM = ["guido", "margaret", "katherine", "tony", "dennis"];

test("a rollout of a hundred takes everyone", () => {
  for (const user of TEAM) {
    assert.strictEqual(rollout.inRollout(user, "checkout-v2", 100), true);
  }
});

test("a rollout of nothing takes no one", () => {
  for (const user of TEAM) {
    assert.strictEqual(rollout.inRollout(user, "checkout-v2", 0), false);
  }
});

test("a caller keeps the bucket it had", () => {
  const first = rollout.bucketFor("guido", "checkout-v2");
  assert.strictEqual(rollout.bucketFor("guido", "checkout-v2"), first);
});

test("one caller sits in two flags apart", () => {
  assert.notStrictEqual(
    rollout.bucketFor("guido", "checkout-v2"),
    rollout.bucketFor("guido", "new-nav"),
  );
});

test("the team splits at a half rollout", () => {
  const inside = TEAM.filter((user) =>
    rollout.inRollout(user, "checkout-v2", 50),
  );
  assert.deepStrictEqual(inside, ["guido", "margaret", "katherine", "tony"]);
});

test("a wider rollout keeps everyone a narrower one had", () => {
  const narrow = TEAM.filter((user) =>
    rollout.inRollout(user, "checkout-v2", 40),
  );
  const wide = TEAM.filter((user) => rollout.inRollout(user, "checkout-v2", 90));
  for (const user of narrow) {
    assert.ok(wide.includes(user), `${user} fell out of the wider rollout`);
  }
});

test("refuses a percentage that is not a whole one in range", () => {
  assert.strictEqual(rollout.inRollout("guido", "checkout-v2", 120), false);
  assert.strictEqual(rollout.inRollout("guido", "checkout-v2", 12.5), false);
  assert.strictEqual(rollout.isPercent(100), true);
  assert.strictEqual(rollout.isPercent(-1), false);
});

test("a caller with no id is outside a rollout of a part", () => {
  assert.strictEqual(rollout.inRollout(undefined, "checkout-v2", 50), false);
  assert.strictEqual(rollout.inRollout("", "checkout-v2", 50), false);
  assert.strictEqual(rollout.inRollout(undefined, "checkout-v2", 100), true);
});
