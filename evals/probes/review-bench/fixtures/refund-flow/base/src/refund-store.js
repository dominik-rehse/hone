// Every refund the shop has made, oldest first. An entry stays here for good,
// so what an order has had back is what its entries come to.

const entries = [];
let nextId = 1;

// Keep one refund. `lines` says what each line of the order got back.
function record({ orderId, amountCents, lines = [], reason = "" }) {
  const entry = {
    id: `r${nextId}`,
    orderId,
    amountCents,
    lines: lines.map((line) => ({ ...line })),
    reason,
    at: Date.now(),
  };
  nextId += 1;
  entries.push(entry);
  return entry;
}

// The refunds of one order, oldest first.
function refundsFor(orderId) {
  return entries.filter((entry) => entry.orderId === orderId);
}

// What the order has had back so far.
function refundedTotal(orderId) {
  return refundsFor(orderId).reduce((total, entry) => total + entry.amountCents, 0);
}

function all() {
  return entries.slice();
}

function reset() {
  entries.length = 0;
  nextId = 1;
}

module.exports = { record, refundsFor, refundedTotal, all, reset };
