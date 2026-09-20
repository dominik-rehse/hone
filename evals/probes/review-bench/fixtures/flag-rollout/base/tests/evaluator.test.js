const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const flag = require("../src/flag.js");
const evaluator = require("../src/evaluator.js");

function put(key, extra = {}) {
  return store.put(flag.makeFlag({ key, ...extra }));
}

test.beforeEach(() => store.reset());

test("an enabled flag is on", () => {
  put("checkout-v2", { enabled: true });
  assert.strictEqual(evaluator.isOn("checkout-v2", { userId: "ada" }), true);
});

test("a disabled flag is off", () => {
  put("checkout-v2");
  assert.strictEqual(evaluator.isOn("checkout-v2", { userId: "ada" }), false);
});

test("a key the list does not carry is off", () => {
  assert.strictEqual(evaluator.isOn("nothing-here", { userId: "ada" }), false);
});

test("an archived flag is off however it was left", () => {
  put("checkout-v2", { enabled: true, tags: ["archived"] });
  assert.strictEqual(evaluator.isOn("checkout-v2", { userId: "ada" }), false);
});

test("works without a context at all", () => {
  put("checkout-v2", { enabled: true });
  assert.strictEqual(evaluator.isOn("checkout-v2"), true);
});

test("names every key that is on", () => {
  put("checkout-v2", { enabled: true });
  put("dark-mode");
  put("new-nav", { enabled: true });
  assert.deepStrictEqual(evaluator.onFor({ userId: "ada" }), [
    "checkout-v2",
    "new-nav",
  ]);
});

test("a snapshot answers for every key the list carries", () => {
  put("checkout-v2", { enabled: true });
  put("dark-mode");
  assert.deepStrictEqual(evaluator.snapshotFor({ userId: "ada" }), {
    "checkout-v2": true,
    "dark-mode": false,
  });
});
