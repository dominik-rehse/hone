const test = require("node:test");
const assert = require("node:assert");
const clock = require("../../src/clock.js");

const t0 = 1_700_000_000_000;

test("reads the time from the source it was given", () => {
  clock.setSource(() => t0);
  assert.strictEqual(clock.now(), t0);
});

test("counts forward from now", () => {
  clock.setSource(() => t0);
  assert.strictEqual(clock.after(250), t0 + 250);
  assert.strictEqual(clock.after(0), t0);
});

test("goes back to the real time", () => {
  clock.setSource(() => t0);
  clock.useRealTime();
  assert.ok(clock.now() > t0);
});
