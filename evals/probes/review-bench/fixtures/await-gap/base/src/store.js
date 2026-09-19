const { isSeat } = require("./seats.js");

// The seats the house has given out, as this process holds them.
const bookings = new Map();
let tick = 0;

// Write the seat to a user, with whatever the till has on the card for it.
function hold(seatId, user, authId = null) {
  if (!isSeat(seatId)) {
    throw new Error(`no such seat: ${seatId}`);
  }
  tick += 1;
  const booking = { seatId, user, authId, at: tick };
  bookings.set(seatId, booking);
  return booking;
}

// Who has the seat, or null when nobody has.
function holderOf(seatId) {
  const booking = bookings.get(seatId);
  return booking === undefined ? null : booking.user;
}

function bookingOf(seatId) {
  return bookings.get(seatId) ?? null;
}

// Take the seat back. True when somebody had it.
function release(seatId) {
  return bookings.delete(seatId);
}

// Every booking one user holds.
function heldBy(user) {
  return [...bookings.values()].filter((booking) => booking.user === user);
}

function count() {
  return bookings.size;
}

// Throw everything away. The tests start from here.
function reset() {
  bookings.clear();
  tick = 0;
}

module.exports = { hold, holderOf, bookingOf, release, heldBy, count, reset };
