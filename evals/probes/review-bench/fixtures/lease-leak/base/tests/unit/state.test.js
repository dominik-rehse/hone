const test = require("node:test");
const assert = require("node:assert");
const state = require("../../src/state.js");

test("has an empty box for a job that never ran", () => {
  state.reset();
  assert.deepStrictEqual(state.load("nightly"), {});
});

test("keeps what a run left behind", () => {
  state.reset();
  state.save("nightly", { cursor: 12 });
  assert.deepStrictEqual(state.load("nightly"), { cursor: 12 });
});

test("hands out a copy, so a step cannot reach into the box", () => {
  state.reset();
  state.save("nightly", { cursor: 12 });
  const loaded = state.load("nightly");
  loaded.cursor = 99;
  assert.deepStrictEqual(state.load("nightly"), { cursor: 12 });
});

test("forgets one job's box", () => {
  state.reset();
  state.save("nightly", { cursor: 12 });
  assert.strictEqual(state.forget("nightly"), true);
  assert.deepStrictEqual(state.load("nightly"), {});
});
