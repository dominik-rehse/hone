const test = require("node:test");
const assert = require("node:assert");
const { createCalendar, addSlot, bookedMinutes } = require("../src/calendar.js");
const { mergeCalendars, isSameBooking, droppedCount } = require("../src/merge.js");

const at = (hour, minute = 0) => hour * 60 + minute;

// The morning team and the afternoon team, who share the Aurora room.
function morningTeam() {
  const cal = createCalendar("Aurora", at(8), at(18));
  addSlot(cal, { start: at(9), end: at(10), title: "Standup", owner: "ana" });
  addSlot(cal, { start: at(10), end: at(11), title: "Design", owner: "ben" });
  addSlot(cal, { start: at(12), end: at(13), title: "All hands", owner: "ana" });
  return cal;
}

function afternoonTeam() {
  const cal = createCalendar("Aurora", at(8), at(18));
  addSlot(cal, { start: at(12), end: at(13), title: "All hands", owner: "ana" });
  addSlot(cal, { start: at(14), end: at(15), title: "Retro", owner: "cleo" });
  addSlot(cal, { start: at(16), end: at(17), title: "Interview", owner: "dev" });
  return cal;
}

test("keeps the bookings of both teams", () => {
  const merged = mergeCalendars(morningTeam(), afternoonTeam());
  assert.deepStrictEqual(
    merged.slots.map((slot) => slot.title),
    ["Standup", "Design", "All hands", "Retro", "Interview"],
  );
  assert.strictEqual(merged.room, "Aurora");
});

test("counts a booking both teams entered once", () => {
  const merged = mergeCalendars(morningTeam(), afternoonTeam());
  const allHands = merged.slots.filter((slot) => slot.title === "All hands");
  assert.strictEqual(allHands.length, 1);
  assert.strictEqual(droppedCount(merged), 0);
});

test("gives the room to the first calendar where two bookings clash", () => {
  const mine = morningTeam();
  const theirs = afternoonTeam();
  addSlot(theirs, { start: at(9, 30), end: at(10, 30), title: "Sync", owner: "cleo" });
  const merged = mergeCalendars(mine, theirs);
  assert.ok(merged.slots.every((slot) => slot.title !== "Sync"));
  assert.deepStrictEqual(
    merged.dropped.map((slot) => slot.title),
    ["Sync"],
  );
  assert.strictEqual(droppedCount(merged), 1);
});

test("leaves the two calendars as they were", () => {
  const mine = morningTeam();
  const theirs = afternoonTeam();
  const before = [mine.slots.length, theirs.slots.length, bookedMinutes(mine)];
  mergeCalendars(mine, theirs);
  assert.deepStrictEqual(
    [mine.slots.length, theirs.slots.length, bookedMinutes(mine)],
    before,
  );
});

test("opens as early and closes as late as either team needs", () => {
  const early = createCalendar("Aurora", at(7), at(16));
  const late = createCalendar("Aurora", at(9), at(20));
  const merged = mergeCalendars(early, late);
  assert.strictEqual(merged.opensAt, at(7));
  assert.strictEqual(merged.closesAt, at(20));
});

test("refuses two calendars that are not for the same room", () => {
  const aurora = createCalendar("Aurora", at(8), at(18));
  const cirrus = createCalendar("Cirrus", at(9), at(17));
  assert.throws(() => mergeCalendars(aurora, cirrus), /Aurora/);
});

test("merges two empty days into an empty day", () => {
  const merged = mergeCalendars(
    createCalendar("Aurora", at(8), at(18)),
    createCalendar("Aurora", at(8), at(18)),
  );
  assert.deepStrictEqual(merged.slots, []);
  assert.strictEqual(droppedCount(merged), 0);
});

test("tells the same booking from one that only looks like it", () => {
  const nine = { start: at(9), end: at(10), title: "Standup", owner: "ana" };
  assert.strictEqual(isSameBooking(nine, { ...nine }), true);
  assert.strictEqual(isSameBooking(nine, { ...nine, owner: "ben" }), false);
  assert.strictEqual(isSameBooking(nine, { ...nine, end: at(10, 30) }), false);
});
