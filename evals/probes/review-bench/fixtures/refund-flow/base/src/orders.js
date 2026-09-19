const money = require("./money.js");

// The orders the shop has taken. An order carries its lines and one
// order-level discount, in whole cents.

const orders = [];
let nextId = 1;

// What one line is worth before the order's discount.
function lineTotal(line) {
  return line.unitCents * line.quantity;
}

// Take a new order. `lines` is [{sku, title, quantity, unitCents}].
function create({ customer, lines, discountCents = 0 }) {
  const order = {
    id: `o${nextId}`,
    customer,
    lines: lines.map((line) => ({ ...line })),
    discountCents,
    placedAt: Date.now(),
  };
  nextId += 1;
  orders.push(order);
  return order;
}

function get(id) {
  return orders.find((order) => order.id === id) ?? null;
}

function all() {
  return orders.slice();
}

function lineOf(order, sku) {
  return order.lines.find((line) => line.sku === sku) ?? null;
}

// What the order is worth: its lines, less its discount.
function orderTotal(order) {
  return money.sum(order.lines.map(lineTotal)) - order.discountCents;
}

// What each line is worth once the order's discount is spread over the lines
// by value. These come to orderTotal(order).
function discountedLineTotals(order) {
  const gross = order.lines.map(lineTotal);
  const cut = money.allocate(order.discountCents, gross);
  return gross.map((amount, i) => amount - cut[i]);
}

function reset() {
  orders.length = 0;
  nextId = 1;
}

module.exports = {
  create,
  get,
  all,
  lineOf,
  lineTotal,
  orderTotal,
  discountedLineTotals,
  reset,
};
