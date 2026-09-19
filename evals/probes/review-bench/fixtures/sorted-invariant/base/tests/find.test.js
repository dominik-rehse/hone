const test = require("node:test");
const assert = require("node:assert");
const { createCalendar, addSlot } = require("../src/calendar.js");
const { findSlot, nextFreeGap, isFree } = require("../src/find.js");

const at = (hour, minute = 0) => hour * 60 + minute;

function day() {
  const cal = createCalendar("Aurora", at(8), at(18));
  addSlot(cal, { start: at(9), end: at(10), title: "Standup" });
  addSlot(cal, { start: at(11), end: at(12), title: "Design" });
  addSlot(cal, { start: at(14), end: at(15), title: "Review" });
  addSlot(cal, { start: at(16), end: at(17), title: "Interview" });
  return cal;
}

test("names the booking that holds the room at a minute", () => {
  const cal = day();
  assert.strictEqual(findSlot(cal, at(9, 30)).title, "Standup");
  assert.strictEqual(findSlot(cal, at(11, 30)).title, "Design");
  assert.strictEqual(findSlot(cal, at(16, 59)).title, "Interview");
});

test("has nothing for a minute the room is free", () => {
  const cal = day();
  assert.strictEqual(findSlot(cal, at(8, 30)), null);
  assert.strictEqual(findSlot(cal, at(13)), null);
  assert.strictEqual(findSlot(cal, at(17, 30)), null);
});

test("counts the first minute of a booking in and the last one out", () => {
  const cal = day();
  assert.strictEqual(findSlot(cal, at(9)).title, "Standup");
  assert.strictEqual(findSlot(cal, at(10)), null);
});

test("has nothing at all on an empty day", () => {
  const cal = createCalendar("Aurora", at(8), at(18));
  assert.strictEqual(findSlot(cal, at(12)), null);
});

test("finds the first free span long enough", () => {
  const cal = day();
  assert.deepStrictEqual(nextFreeGap(cal, at(8), 30), { start: at(8), end: at(8, 30) });
  assert.deepStrictEqual(nextFreeGap(cal, at(11), 90), { start: at(12), end: at(13, 30) });
  assert.deepStrictEqual(nextFreeGap(cal, at(9, 30), 60), { start: at(10), end: at(11) });
});

test("walks past one booking after another to find room", () => {
  const cal = day();
  assert.deepStrictEqual(nextFreeGap(cal, at(14), 60), { start: at(15), end: at(16) });
  assert.deepStrictEqual(nextFreeGap(cal, at(16), 45), { start: at(17), end: at(17, 45) });
});

test("has no free span when the room closes first", () => {
  const cal = day();
  assert.strictEqual(nextFreeGap(cal, at(16), 120), null);
});

test("answers whether a whole span is free", () => {
  const cal = day();
  assert.strictEqual(isFree(cal, at(12), at(14)), true);
  assert.strictEqual(isFree(cal, at(10), at(11)), true);
  assert.strictEqual(isFree(cal, at(11, 30), at(13)), false);
  assert.strictEqual(isFree(cal, at(7), at(8, 30)), false);
});
