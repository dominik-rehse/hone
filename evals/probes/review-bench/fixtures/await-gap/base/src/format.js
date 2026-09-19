const { parseSeat } = require("./seats.js");

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

module.exports = {
  formatMoney,
  formatSeat,
  formatBooking,
  formatRefusal,
  formatSeatMap,
  REASONS,
};
