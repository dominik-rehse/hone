const { overlaps, spanMinutes } = require("./time.js");

// The day's bookings for one room, between the hours the room is open.
function createCalendar(room, opensAt, closesAt) {
  return { room, opensAt, closesAt, slots: [] };
}

// Where a booking that begins at `start` goes among the ones already made.
function indexFor(slots, start) {
  let lo = 0;
  let hi = slots.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (slots[mid].start <= start) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

// Book the room. Gives back the booking, or null when the span is empty, falls
// outside the opening hours, or wants minutes somebody else already has.
function addSlot(calendar, { start, end, title, owner = null }) {
  if (!(start < end)) {
    return null;
  }
  if (start < calendar.opensAt || end > calendar.closesAt) {
    return null;
  }
  const slot = { start, end, title, owner };
  if (calendar.slots.some((other) => overlaps(other, slot))) {
    return null;
  }
  calendar.slots.splice(indexFor(calendar.slots, start), 0, slot);
  return slot;
}

// Give back the booking that begins at `start`, or null when there is none.
function removeSlot(calendar, start) {
  const at = calendar.slots.findIndex((slot) => slot.start === start);
  if (at === -1) {
    return null;
  }
  return calendar.slots.splice(at, 1)[0];
}

// How many minutes of the opening hours are booked.
function bookedMinutes(calendar) {
  return calendar.slots.reduce((sum, slot) => sum + spanMinutes(slot), 0);
}

// How many minutes of the opening hours are still free.
function freeMinutes(calendar) {
  return calendar.closesAt - calendar.opensAt - bookedMinutes(calendar);
}

module.exports = {
  createCalendar,
  indexFor,
  addSlot,
  removeSlot,
  bookedMinutes,
  freeMinutes,
};
