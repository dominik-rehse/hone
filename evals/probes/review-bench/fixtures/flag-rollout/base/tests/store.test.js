const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const flag = require("../src/flag.js");

function put(key, extra = {}) {
  return store.put(flag.makeFlag({ key, ...extra }));
}

test.beforeEach(() => store.reset());

test("puts a flag on the list and reads it back", () => {
  put("checkout-v2", { owner: "payments" });
  assert.strictEqual(store.get("checkout-v2").owner, "payments");
  assert.strictEqual(store.has("checkout-v2"), true);
});

test("gives null for a key it does not carry", () => {
  assert.strictEqual(store.get("nothing-here"), null);
  assert.strictEqual(store.has("nothing-here"), false);
});

test("a second put under one key replaces the first", () => {
  put("checkout-v2", { owner: "payments" });
  put("checkout-v2", { owner: "web" });
  assert.strictEqual(store.size(), 1);
  assert.strictEqual(store.get("checkout-v2").owner, "web");
});

test("lists its keys in order", () => {
  put("new-nav");
  put("checkout-v2");
  put("dark-mode");
  assert.deepStrictEqual(store.keys(), ["checkout-v2", "dark-mode", "new-nav"]);
  assert.deepStrictEqual(
    store.all().map((one) => one.key),
    ["checkout-v2", "dark-mode", "new-nav"],
  );
});

test("takes a flag off and says whether it was there", () => {
  put("checkout-v2");
  assert.strictEqual(store.remove("checkout-v2"), true);
  assert.strictEqual(store.remove("checkout-v2"), false);
  assert.strictEqual(store.size(), 0);
});
