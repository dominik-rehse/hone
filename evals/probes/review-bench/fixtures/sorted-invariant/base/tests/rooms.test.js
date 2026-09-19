const test = require("node:test");
const assert = require("node:assert");
const rooms = require("../src/rooms.js");

test("finds a room by its name, and nothing for one the office has not", () => {
  assert.strictEqual(rooms.roomNamed("Aurora").seats, 12);
  assert.strictEqual(rooms.roomNamed("Nimbus"), null);
});

test("opens a fresh calendar on the room's own hours", () => {
  const cal = rooms.calendarFor("Cirrus");
  assert.strictEqual(cal.room, "Cirrus");
  assert.strictEqual(cal.opensAt, 9 * 60);
  assert.strictEqual(cal.closesAt, 17 * 60);
  assert.deepStrictEqual(cal.slots, []);
});

test("has no calendar for a room the office has not", () => {
  assert.strictEqual(rooms.calendarFor("Nimbus"), null);
});

test("offers the smallest room a party fits in first", () => {
  assert.deepStrictEqual(
    rooms.roomsFor(5).map((room) => room.name),
    ["Borealis", "Aurora"],
  );
  assert.deepStrictEqual(
    rooms.roomsFor(3).map((room) => room.name),
    ["Cirrus", "Borealis", "Aurora"],
  );
});

test("offers nothing for a party no room holds", () => {
  assert.deepStrictEqual(rooms.roomsFor(40), []);
});

test("lists the rooms of one floor as the sheet has them", () => {
  assert.deepStrictEqual(
    rooms.roomsOnFloor(2).map((room) => room.name),
    ["Borealis", "Cirrus"],
  );
});
