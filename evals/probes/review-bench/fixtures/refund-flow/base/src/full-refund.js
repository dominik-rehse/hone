const orders = require("./orders.js");
const payments = require("./payments.js");
const refundStore = require("./refund-store.js");
const ledger = require("./ledger.js");
const money = require("./money.js");

// Give a whole order back in one go. An order that has had anything back
// belongs on the line-by-line path instead.
function refundWhole(orderId, reason) {
  const order = orders.get(orderId);
  if (order === null) {
    throw new Error(`no order ${orderId}`);
  }
  const back = refundStore.refundedTotal(orderId);
  if (back > 0) {
    throw new Error(`${orderId} has had ${money.format(back)} back already`);
  }
  const net = orders.discountedLineTotals(order);
  const amountCents = orders.orderTotal(order);
  const lines = order.lines.map((line, i) => ({ sku: line.sku, amountCents: net[i] }));
  payments.markRefunded(orderId, amountCents);
  const entry = refundStore.record({ orderId, amountCents, lines, reason });
  ledger.post({ orderId, kind: "refund", amountCents, memo: reason });
  return entry;
}

module.exports = { refundWhole };
