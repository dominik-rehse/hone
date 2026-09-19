const money = require("./money.js");

// The money that moved. One entry per movement, and an entry is never changed
// and never taken out.

const entries = [];
let nextId = 1;

// Money in is a payment. Money out is a refund or a fee.
const SIGN = { payment: 1, refund: -1, fee: -1 };

function post({ orderId, kind, amountCents, memo = "" }) {
  if (SIGN[kind] === undefined) {
    throw new Error(`unknown ledger kind ${kind}`);
  }
  const entry = { id: `l${nextId}`, orderId, kind, amountCents, memo, at: Date.now() };
  nextId += 1;
  entries.push(entry);
  return entry;
}

function entriesFor(orderId) {
  return entries.filter((entry) => entry.orderId === orderId);
}

// What one order's entries of one kind come to.
function totalOf(orderId, kind) {
  return money.sum(
    entriesFor(orderId)
      .filter((entry) => entry.kind === kind)
      .map((entry) => entry.amountCents),
  );
}

// What the shop is holding over every order.
function balance() {
  return money.sum(entries.map((entry) => SIGN[entry.kind] * entry.amountCents));
}

function all() {
  return entries.slice();
}

function reset() {
  entries.length = 0;
  nextId = 1;
}

module.exports = { post, entriesFor, totalOf, balance, all, reset, SIGN };
