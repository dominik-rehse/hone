const test = require("node:test");
const assert = require("node:assert");
const { createCalendar, addSlot, removeSlot, bookedMinutes, freeMinutes } =
  require("../src/calendar.js");

const OPEN = 8 * 60;
const CLOSE = 18 * 60;
const at = (hour, minute = 0) => hour * 60 + minute;

function day() {
  return createCalendar("Aurora", OPEN, CLOSE);
}

test("a fresh day has no bookings and its whole span free", () => {
  const cal = day();
  assert.deepStrictEqual(cal.slots, []);
  assert.strictEqual(bookedMinutes(cal), 0);
  assert.strictEqual(freeMinutes(cal), CLOSE - OPEN);
});

test("books a span and gives the booking back", () => {
  const cal = day();
  const slot = addSlot(cal, { start: at(9), end: at(10), title: "Standup" });
  assert.strictEqual(slot.title, "Standup");
  assert.strictEqual(cal.slots.length, 1);
  assert.strictEqual(bookedMinutes(cal), 60);
});

test("refuses a span the room already holds", () => {
  const cal = day();
  addSlot(cal, { start: at(9), end: at(10), title: "Standup" });
  assert.strictEqual(addSlot(cal, { start: at(9, 30), end: at(10, 30), title: "Design" }), null);
  assert.strictEqual(cal.slots.length, 1);
});

test("lets one booking begin where another ends", () => {
  const cal = day();
  addSlot(cal, { start: at(9), end: at(10), title: "Standup" });
  assert.notStrictEqual(addSlot(cal, { start: at(10), end: at(11), title: "Design" }), null);
  assert.strictEqual(cal.slots.length, 2);
});

test("refuses an empty span and one outside the opening hours", () => {
  const cal = day();
  assert.strictEqual(addSlot(cal, { start: at(9), end: at(9), title: "Nothing" }), null);
  assert.strictEqual(addSlot(cal, { start: at(7), end: at(8), title: "Early" }), null);
  assert.strictEqual(addSlot(cal, { start: at(17), end: at(19), title: "Late" }), null);
  assert.strictEqual(cal.slots.length, 0);
});

test("keeps the bookings of a day in the order the clock runs", () => {
  const cal = day();
  addSlot(cal, { start: at(15), end: at(16), title: "Retro" });
  addSlot(cal, { start: at(9), end: at(10), title: "Standup" });
  addSlot(cal, { start: at(11), end: at(12), title: "Design" });
  assert.deepStrictEqual(
    cal.slots.map((slot) => slot.title),
    ["Standup", "Design", "Retro"],
  );
});

test("gives a booking back and frees its minutes", () => {
  const cal = day();
  addSlot(cal, { start: at(9), end: at(10), title: "Standup" });
  addSlot(cal, { start: at(11), end: at(12), title: "Design" });
  const gone = removeSlot(cal, at(9));
  assert.strictEqual(gone.title, "Standup");
  assert.strictEqual(cal.slots.length, 1);
  assert.strictEqual(freeMinutes(cal), CLOSE - OPEN - 60);
});

test("has nothing to give back for a span nobody booked", () => {
  const cal = day();
  assert.strictEqual(removeSlot(cal, at(9)), null);
});

test("remembers who a booking is for", () => {
  const cal = day();
  const slot = addSlot(cal, { start: at(9), end: at(10), title: "Standup", owner: "ana" });
  assert.strictEqual(slot.owner, "ana");
  assert.strictEqual(addSlot(cal, { start: at(11), end: at(12), title: "Design" }).owner, null);
});
