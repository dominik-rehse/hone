const { parseTime } = require("./time.js");
const { createCalendar } = require("./calendar.js");

// The rooms the office books, as the facilities sheet lists them.
const ROOMS = [
  { name: "Aurora", seats: 12, opens: "08:00", closes: "18:00", floor: 1 },
  { name: "Borealis", seats: 6, opens: "08:00", closes: "20:00", floor: 2 },
  { name: "Cirrus", seats: 4, opens: "09:00", closes: "17:00", floor: 2 },
];

function roomNamed(name) {
  return ROOMS.find((room) => room.name === name) ?? null;
}

// A fresh day's calendar for one room, or null when there is no such room.
function calendarFor(name) {
  const room = roomNamed(name);
  if (room === null) {
    return null;
  }
  return createCalendar(room.name, parseTime(room.opens), parseTime(room.closes));
}

// The rooms that seat a party of `people`, the smallest first.
function roomsFor(people) {
  return ROOMS.filter((room) => room.seats >= people).sort((a, b) => a.seats - b.seats);
}

// The rooms on one floor, in the order the sheet lists them.
function roomsOnFloor(floor) {
  return ROOMS.filter((room) => room.floor === floor);
}

module.exports = { ROOMS, roomNamed, calendarFor, roomsFor, roomsOnFloor };
