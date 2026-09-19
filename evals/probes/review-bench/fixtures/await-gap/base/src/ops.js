const store = require("./store.js");
const seats = require("./seats.js");
const { withLock } = require("./lock.js");

// Hold a free seat for a user.
function reserve(seatId, user) {
  const price = seats.priceOf(seatId);
  if (price === null) {
    return { ok: false, reason: "no-such-seat", seatId };
  }
  if (store.holderOf(seatId) !== null) {
    return { ok: false, reason: "taken", seatId };
  }
  return { ok: true, booking: store.hold(seatId, user), price };
}

// Every seat one user holds, in the order they took them.
function bookingsOf(user) {
  return store.heldBy(user).sort((one, other) => one.at - other.at);
}

// How the house stands: every seat of it, and who has it.
function seatMap() {
  return seats.allSeats().map((seatId) => ({ seatId, user: store.holderOf(seatId) }));
}

// How many seats are still to be had.
function seatsLeft() {
  return seats.allSeats().length - store.count();
}

// Give a seat back.
function cancel(seatId, user) {
  return withLock(seatId, () => {
    if (store.holderOf(seatId) !== user) {
      return { ok: false, reason: "not-yours", seatId };
    }
    store.release(seatId);
    return { ok: true, seatId };
  });
}

// Move a user to a free seat in the row they already paid for.
function swap(fromId, toId, user) {
  return withLock(toId, () => {
    if (store.holderOf(fromId) !== user) {
      return { ok: false, reason: "not-yours", seatId: fromId };
    }
    if (seats.rowOf(toId) !== seats.rowOf(fromId)) {
      return { ok: false, reason: "other-row", seatId: toId };
    }
    if (store.holderOf(toId) !== null) {
      return { ok: false, reason: "taken", seatId: toId };
    }
    const { authId } = store.bookingOf(fromId);
    store.release(fromId);
    return { ok: true, booking: store.hold(toId, user, authId) };
  });
}

module.exports = { reserve, bookingsOf, seatMap, seatsLeft, cancel, swap };
