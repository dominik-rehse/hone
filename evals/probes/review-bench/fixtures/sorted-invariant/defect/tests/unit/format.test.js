const test = require("node:test");
const assert = require("node:assert");
const format = require("../../src/format.js");
const { createCalendar, addSlot } = require("../../src/calendar.js");
const { mergeCalendars } = require("../../src/merge.js");

const at = (hour, minute = 0) => hour * 60 + minute;

test("puts one booking on one line", () => {
  assert.strictEqual(
    format.formatSlot({ start: at(9), end: at(10), title: "Standup", owner: "ana" }),
    "09:00-10:00  Standup",
  );
});

test("reads a length as hours and minutes", () => {
  assert.strictEqual(format.formatLength(45), "45m");
  assert.strictEqual(format.formatLength(90), "1h 30m");
  assert.strictEqual(format.formatLength(120), "2h");
});

test("lists a day under the room and its hours", () => {
  const cal = createCalendar("Aurora", at(8), at(18));
  addSlot(cal, { start: at(9), end: at(10), title: "Standup" });
  addSlot(cal, { start: at(11), end: at(12), title: "Design" });
  assert.strictEqual(
    format.formatDay(cal),
    ["Aurora  08:00-18:00", "  09:00-10:00  Standup", "  11:00-12:00  Design"].join("\n"),
  );
});

test("lists an empty day as its heading alone", () => {
  const cal = createCalendar("Cirrus", at(9), at(17));
  assert.strictEqual(format.formatDay(cal), "Cirrus  09:00-17:00");
});

test("writes a free span with how long it runs", () => {
  assert.strictEqual(
    format.formatGap({ start: at(12), end: at(13, 30) }),
    "free 12:00-13:30 (1h 30m)",
  );
});

test("says so when the day has no free span left", () => {
  assert.strictEqual(format.formatGap(null), "no free span left today");
});

test("names the team a booking is for, and says so when there is none", () => {
  assert.strictEqual(format.ownerOf({ owner: "ana" }), "ana");
  assert.strictEqual(format.ownerOf({ owner: null }), "nobody in particular");
  assert.strictEqual(format.ownerOf({}), "nobody in particular");
});

test("lists what a merge could not keep under the day", () => {
  const mine = createCalendar("Aurora", at(8), at(18));
  addSlot(mine, { start: at(9), end: at(10), title: "Standup", owner: "ana" });
  const theirs = createCalendar("Aurora", at(8), at(18));
  addSlot(theirs, { start: at(9, 30), end: at(10, 30), title: "Sync", owner: "cleo" });
  assert.strictEqual(
    format.formatMerged(mergeCalendars(mine, theirs)),
    [
      "Aurora  08:00-18:00",
      "  09:00-10:00  Standup",
      "  could not keep 1:",
      "    09:30-10:30  Sync  for cleo",
    ].join("\n"),
  );
});

test("lists a merge that kept everything as a plain day", () => {
  const mine = createCalendar("Aurora", at(8), at(18));
  addSlot(mine, { start: at(9), end: at(10), title: "Standup", owner: "ana" });
  const theirs = createCalendar("Aurora", at(8), at(18));
  addSlot(theirs, { start: at(14), end: at(15), title: "Retro", owner: "cleo" });
  const merged = mergeCalendars(mine, theirs);
  assert.strictEqual(format.formatMerged(merged), format.formatDay(merged));
});
