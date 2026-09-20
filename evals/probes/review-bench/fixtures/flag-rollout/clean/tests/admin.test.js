const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const audit = require("../src/audit.js");
const clock = require("../src/clock.js");
const admin = require("../src/admin.js");

test.beforeEach(() => {
  store.reset();
  audit.clear();
  let tick = 1000;
  clock.setClock(() => {
    tick += 1;
    return tick;
  });
});

test.after(() => clock.useRealClock());

test("creates a flag and writes it down", () => {
  admin.create({ key: "checkout-v2", owner: "payments" }, "ada");
  assert.strictEqual(store.get("checkout-v2").owner, "payments");
  const entry = audit.last();
  assert.strictEqual(entry.action, "create");
  assert.strictEqual(entry.actor, "ada");
  assert.strictEqual(entry.before, null);
  assert.strictEqual(entry.after.key, "checkout-v2");
});

test("refuses a second flag under one key", () => {
  admin.create({ key: "checkout-v2" }, "ada");
  assert.throws(() => admin.create({ key: "checkout-v2" }, "ada"), RangeError);
});

test("refuses to touch a flag that is not there", () => {
  assert.throws(() => admin.setEnabled("nothing-here", true, "ada"), RangeError);
});

test("an enable writes down what it was and what it is", () => {
  admin.create({ key: "checkout-v2" }, "ada");
  admin.setEnabled("checkout-v2", true, "grace");
  const entry = audit.last();
  assert.strictEqual(entry.action, "enable");
  assert.strictEqual(entry.before.enabled, false);
  assert.strictEqual(entry.after.enabled, true);
});

test("a description change writes down the old line", () => {
  admin.create({ key: "checkout-v2", description: "first go" }, "ada");
  admin.setDescription("checkout-v2", "second go", "grace");
  const entry = audit.last();
  assert.strictEqual(entry.before.description, "first go");
  assert.strictEqual(entry.after.description, "second go");
});

test("a tag goes on once", () => {
  admin.create({ key: "checkout-v2" }, "ada");
  admin.addTag("checkout-v2", "billing", "ada");
  admin.addTag("checkout-v2", "billing", "ada");
  assert.deepStrictEqual(store.get("checkout-v2").tags, ["billing"]);
  assert.strictEqual(admin.history("checkout-v2").length, 2);
});

test("a removal keeps the flag as it last was", () => {
  admin.create({ key: "checkout-v2", owner: "payments" }, "ada");
  const gone = admin.remove("checkout-v2", "grace");
  assert.strictEqual(gone.owner, "payments");
  assert.strictEqual(store.has("checkout-v2"), false);
  assert.strictEqual(audit.last().after, null);
});

test("every entry carries the time it was written", () => {
  admin.create({ key: "checkout-v2" }, "ada");
  admin.setEnabled("checkout-v2", true, "ada");
  const [first, second] = audit.all();
  assert.ok(second.at > first.at);
});

test("reads the list one line per flag", () => {
  admin.create({ key: "new-nav", owner: "web" }, "ada");
  admin.create({ key: "checkout-v2", owner: "payments" }, "ada");
  admin.setEnabled("checkout-v2", true, "ada");
  admin.setRollout("checkout-v2", 20, "ada");
  assert.deepStrictEqual(admin.listing(), [
    "checkout-v2 on (payments) 20%",
    "new-nav off (web) all",
  ]);
});

test("puts a rollout on a flag and writes the move down", () => {
  admin.create({ key: "checkout-v2" }, "ada");
  admin.setRollout("checkout-v2", 25, "grace");
  assert.strictEqual(store.get("checkout-v2").rollout.percent, 25);
  const entry = audit.last();
  assert.strictEqual(entry.action, "set-rollout");
  assert.strictEqual(entry.actor, "grace");
  assert.strictEqual(entry.after.rollout.percent, 25);
});

test("refuses a percentage that is not a whole one in range", () => {
  admin.create({ key: "checkout-v2" }, "ada");
  assert.throws(() => admin.setRollout("checkout-v2", 101, "grace"), RangeError);
  assert.throws(() => admin.setRollout("checkout-v2", -5, "grace"), RangeError);
  assert.throws(
    () => admin.setRollout("checkout-v2", 12.5, "grace"),
    RangeError,
  );
});

test("a moved rollout keeps its first day and takes a new time", () => {
  admin.create({ key: "checkout-v2" }, "ada");
  admin.setRollout("checkout-v2", 10, "grace");
  const { since, updatedAt } = store.get("checkout-v2").rollout;
  admin.setRollout("checkout-v2", 40, "grace");
  assert.strictEqual(store.get("checkout-v2").rollout.since, since);
  assert.ok(store.get("checkout-v2").rollout.updatedAt > updatedAt);
});

test("refuses a flag made with a rollout that is not one", () => {
  assert.throws(
    () => admin.create({ key: "checkout-v2", rollout: { percent: 150 } }, "ada"),
    RangeError,
  );
});

test("clearing a rollout keeps the one it had in the log", () => {
  admin.create({ key: "checkout-v2" }, "ada");
  admin.setRollout("checkout-v2", 25, "grace");
  admin.clearRollout("checkout-v2", "grace");
  assert.strictEqual(store.get("checkout-v2").rollout, undefined);
  const entry = audit.last();
  assert.strictEqual(entry.action, "clear-rollout");
  assert.strictEqual(entry.before.rollout.percent, 25);
  assert.strictEqual(entry.after.rollout, undefined);
});

test("a preview cuts a list of callers in two without touching the flag", () => {
  admin.create({ key: "checkout-v2" }, "ada");
  const seen = admin.previewRollout("checkout-v2", 50, [
    "guido",
    "margaret",
    "dennis",
  ]);
  assert.deepStrictEqual(seen.inside, ["guido", "margaret"]);
  assert.deepStrictEqual(seen.outside, ["dennis"]);
  assert.strictEqual(store.get("checkout-v2").rollout, undefined);
});
