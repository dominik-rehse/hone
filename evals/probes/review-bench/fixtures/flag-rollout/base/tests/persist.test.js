const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const flag = require("../src/flag.js");
const persist = require("../src/persist.js");
const serializer = require("../src/serializer.js");

test.beforeEach(() => store.reset());

test("saves the list and reads it back whole", () => {
  store.put(
    flag.makeFlag({
      key: "checkout-v2",
      description: "the new checkout",
      enabled: true,
      owner: "payments",
      tags: ["billing"],
    }),
  );
  store.put(flag.makeFlag({ key: "new-nav", owner: "web" }));

  const text = persist.save();
  store.reset();
  assert.strictEqual(persist.restore(text), 2);

  const back = store.get("checkout-v2");
  assert.strictEqual(back.description, "the new checkout");
  assert.strictEqual(back.enabled, true);
  assert.strictEqual(back.owner, "payments");
  assert.deepStrictEqual(back.tags, ["billing"]);
  assert.strictEqual(store.get("new-nav").enabled, false);
});

test("a restore replaces the list that was there", () => {
  store.put(flag.makeFlag({ key: "checkout-v2" }));
  const text = persist.save();
  store.put(flag.makeFlag({ key: "new-nav" }));
  persist.restore(text);
  assert.deepStrictEqual(store.keys(), ["checkout-v2"]);
});

test("refuses a save from a version it does not know", () => {
  assert.throws(
    () => persist.restore(JSON.stringify({ version: 7, flags: [] })),
    RangeError,
  );
});

test("a record reads a flag's own fields back", () => {
  const one = flag.makeFlag({ key: "checkout-v2", owner: "payments" });
  const record = serializer.toRecord(one);
  assert.strictEqual(record.key, "checkout-v2");
  assert.strictEqual(record.owner, "payments");
  assert.strictEqual(record.enabled, false);
  assert.strictEqual(serializer.fromRecord(record).owner, "payments");
});
