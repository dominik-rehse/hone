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
  assert.deepStrictEqual(admin.listing(), [
    "checkout-v2 on (payments)",
    "new-nav off (web)",
  ]);
});
