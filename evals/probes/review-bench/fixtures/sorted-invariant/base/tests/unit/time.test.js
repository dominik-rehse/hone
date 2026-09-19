const test = require("node:test");
const assert = require("node:assert");
const time = require("../../src/time.js");

test("reads a time of day as minutes since midnight", () => {
  assert.strictEqual(time.parseTime("09:30"), 570);
  assert.strictEqual(time.parseTime("0:00"), 0);
  assert.strictEqual(time.parseTime(" 23:59 "), 1439);
});

test("refuses text that is not a time of day", () => {
  assert.throws(() => time.parseTime("9.30"));
  assert.throws(() => time.parseTime("24:00"));
  assert.throws(() => time.parseTime("09:70"));
});

test("writes minutes back as a time of day", () => {
  assert.strictEqual(time.formatTime(570), "09:30");
  assert.strictEqual(time.formatTime(0), "00:00");
  assert.strictEqual(time.formatTime(1439), "23:59");
});

test("measures how long a span runs", () => {
  assert.strictEqual(time.spanMinutes({ start: 540, end: 630 }), 90);
});

test("says two spans overlap only where they share a minute", () => {
  const nine = { start: 540, end: 600 };
  assert.strictEqual(time.overlaps(nine, { start: 570, end: 630 }), true);
  assert.strictEqual(time.overlaps(nine, { start: 600, end: 660 }), false);
  assert.strictEqual(time.overlaps(nine, { start: 480, end: 540 }), false);
  assert.strictEqual(time.overlaps(nine, { start: 550, end: 560 }), true);
});

test("says a span contains another only when it holds all of it", () => {
  const morning = { start: 480, end: 720 };
  assert.strictEqual(time.contains(morning, { start: 540, end: 600 }), true);
  assert.strictEqual(time.contains(morning, { start: 480, end: 720 }), true);
  assert.strictEqual(time.contains(morning, { start: 700, end: 760 }), false);
});
