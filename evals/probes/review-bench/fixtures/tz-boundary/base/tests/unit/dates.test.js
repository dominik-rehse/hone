const test = require("node:test");
const assert = require("node:assert");
const dates = require("../../src/dates.js");

test("reads a written date", () => {
  assert.strictEqual(dates.toIsoDate(dates.fromIsoDate("2026-01-08")), "2026-01-08");
  assert.strictEqual(dates.toIsoDate(dates.fromIsoDate(" 2026-12-31 ")), "2026-12-31");
});

test("refuses text that is not a date", () => {
  assert.throws(() => dates.fromIsoDate("8.1.2026"));
  assert.throws(() => dates.fromIsoDate("2026-1-8"));
  assert.throws(() => dates.fromIsoDate(""));
});

test("counts days on", () => {
  const issued = dates.fromIsoDate("2026-01-08");
  assert.strictEqual(dates.toIsoDate(dates.addDaysUtc(issued, 30)), "2026-02-07");
  assert.strictEqual(dates.toIsoDate(dates.addDaysUtc(issued, 0)), "2026-01-08");
});

test("counts days on over the turn of a year", () => {
  const issued = dates.fromIsoDate("2025-12-20");
  assert.strictEqual(dates.toIsoDate(dates.addDaysUtc(issued, 30)), "2026-01-19");
});

test("counts the days between two days", () => {
  const from = dates.fromIsoDate("2026-01-08");
  const to = dates.fromIsoDate("2026-02-07");
  assert.strictEqual(dates.daysBetweenUtc(from, to), 30);
  assert.strictEqual(dates.daysBetweenUtc(to, from), -30);
  assert.strictEqual(dates.daysBetweenUtc(from, from), 0);
});

test("says which of two days falls later", () => {
  const early = dates.fromIsoDate("2026-01-08");
  const late = dates.fromIsoDate("2026-01-09");
  assert.strictEqual(dates.isAfterUtc(late, early), true);
  assert.strictEqual(dates.isAfterUtc(early, late), false);
  assert.strictEqual(dates.isAfterUtc(early, early), false);
});
