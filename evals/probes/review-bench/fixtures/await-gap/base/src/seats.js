// A seat id is a row letter and a number, "A-1" through "C-12".

const ROWS = ["A", "B", "C"];
const SEATS_PER_ROW = 12;
const ROW_PRICE_CENTS = { A: 4800, B: 3600, C: 2400 };

function seatId(row, number) {
  return `${row}-${number}`;
}

// The row and the number behind a seat id, or null when there is no such seat.
function parseSeat(id) {
  const m = /^([A-Z])-([1-9]\d?)$/.exec(String(id));
  if (m === null) {
    return null;
  }
  const number = Number(m[2]);
  if (!ROWS.includes(m[1]) || number > SEATS_PER_ROW) {
    return null;
  }
  return { row: m[1], number };
}

function isSeat(id) {
  return parseSeat(id) !== null;
}

// The row a seat sits in, or null when the house has no such seat.
function rowOf(id) {
  const seat = parseSeat(id);
  return seat === null ? null : seat.row;
}

// What the seat costs in whole cents, or null when the house has no such seat.
function priceOf(id) {
  const seat = parseSeat(id);
  return seat === null ? null : ROW_PRICE_CENTS[seat.row];
}

// Every seat of the house, row by row and left to right.
function allSeats() {
  const ids = [];
  for (const row of ROWS) {
    for (let number = 1; number <= SEATS_PER_ROW; number += 1) {
      ids.push(seatId(row, number));
    }
  }
  return ids;
}

// The seat to the right of this one, or null at the end of the row.
function nextSeat(id) {
  const seat = parseSeat(id);
  if (seat === null || seat.number === SEATS_PER_ROW) {
    return null;
  }
  return seatId(seat.row, seat.number + 1);
}

module.exports = {
  ROWS,
  SEATS_PER_ROW,
  ROW_PRICE_CENTS,
  seatId,
  parseSeat,
  isSeat,
  rowOf,
  priceOf,
  allSeats,
  nextSeat,
};
