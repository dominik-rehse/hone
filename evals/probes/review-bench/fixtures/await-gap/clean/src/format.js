const { parseSeat, priceOf } = require("./seats.js");

// Whole cents as money on a ticket.
function formatMoney(cents) {
  return `${(cents / 100).toFixed(2)} EUR`;
}

// A seat id as the ticket prints it.
function formatSeat(seatId) {
  const seat = parseSeat(seatId);
  return seat === null ? `seat ${seatId}` : `row ${seat.row}, seat ${seat.number}`;
}

// The line the till shows for one booking.
function formatBooking(booking) {
  return `${formatSeat(booking.seatId)} for ${booking.user}`;
}

const REASONS = {
  taken: "somebody else has that seat",
  "not-yours": "that seat is not yours to move",
  "no-such-seat": "the house has no such seat",
  "other-row": "that seat is in another row",
  declined: "the card was turned down",
  "short-hold": "the card would not hold the whole price",
};

// What a refusal reads like at the till.
function formatRefusal(result) {
  return REASONS[result.reason] ?? `cannot do that: ${result.reason}`;
}

// The house, row by row, with a taken seat marked.
function formatSeatMap(map) {
  const rows = new Map();
  for (const seat of map) {
    const row = seat.seatId.split("-")[0];
    rows.set(row, (rows.get(row) ?? "") + (seat.user === null ? "." : "x"));
  }
  return [...rows.entries()].map(([row, marks]) => `${row} ${marks}`).join("\n");
}

// What the card is holding for a booking, for the till's slip.
function formatHold(booking) {
  return booking.authId == null ? "nothing on the card" : `card hold ${booking.authId}`;
}

// The slip the till prints once a booking has gone through, or the refusal in
// words when it has not.
function formatConfirmation(result) {
  if (!result.ok) {
    return formatRefusal(result);
  }
  return [
    formatBooking(result.booking),
    formatMoney(priceOf(result.booking.seatId)),
    formatHold(result.booking),
  ].join(" - ");
}

module.exports = {
  formatMoney,
  formatSeat,
  formatBooking,
  formatRefusal,
  formatSeatMap,
  formatHold,
  formatConfirmation,
  REASONS,
};
