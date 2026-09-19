const { overlaps } = require("./time.js");

// Two teams that share a room enter the same standing booking in both
// calendars. Such a pair counts once.
function isSameBooking(a, b) {
  return (
    a.start === b.start && a.end === b.end && a.title === b.title && a.owner === b.owner
  );
}

// Put the two calendars of a shared room together.
//
// A booking both calendars hold counts once. Where two bookings want minutes
// the room cannot give twice, the one from the first calendar keeps the room
// and the other goes on the `dropped` list, for the note that goes out to the
// team that loses it. Neither calendar is touched.
function mergeCalendars(a, b) {
  if (a.room !== b.room) {
    throw new Error(`two rooms cannot merge: ${a.room} and ${b.room}`);
  }
  const kept = [];
  const dropped = [];
  for (const slot of [...a.slots, ...b.slots]) {
    if (kept.some((other) => isSameBooking(other, slot))) {
      continue;
    }
    if (kept.some((other) => overlaps(other, slot))) {
      dropped.push({ ...slot });
      continue;
    }
    kept.push({ ...slot });
  }
  kept.sort((one, other) => one.start - other.start);
  return {
    room: a.room,
    opensAt: Math.min(a.opensAt, b.opensAt),
    closesAt: Math.max(a.closesAt, b.closesAt),
    slots: kept,
    dropped,
  };
}

// How many of the two calendars' bookings the merge could not keep.
function droppedCount(calendar) {
  return (calendar.dropped ?? []).length;
}

module.exports = { isSameBooking, mergeCalendars, droppedCount };
