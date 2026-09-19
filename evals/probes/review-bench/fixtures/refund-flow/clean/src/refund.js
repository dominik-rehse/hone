const orders = require("./orders.js");
const payments = require("./payments.js");
const ledger = require("./ledger.js");
const refundStore = require("./refund-store.js");
const notify = require("./notify.js");
const money = require("./money.js");
const { pickSkus, refundShares } = require("./refund-lines.js");

// Give part of an order back. `lines` names the order lines to give back, by
// sku, and an empty list means all of them. `reason` goes on the entry the
// store keeps and into the mail the customer gets.
function refund(orderId, lines, reason) {
  const order = orders.get(orderId);
  if (order === null) {
    throw new Error(`no order ${orderId}`);
  }
  const skus = pickSkus(order, lines);
  const shares = refundShares(order, skus);
  const amountCents = money.sum(shares.map((share) => share.amountCents));
  if (amountCents <= 0) {
    throw new Error(`a refund on ${orderId} would be for nothing`);
  }
  const back = refundStore.refundsFor(orderId);
  for (const sku of skus) {
    if (back.some((entry) => entry.lines.some((line) => line.sku === sku))) {
      throw new Error(`${orderId} has had ${sku} back already`);
    }
  }
  const limit = orders.orderTotal(order) - refundStore.refundedTotal(orderId);
  if (amountCents > limit) {
    throw new Error(
      `a refund of ${money.format(amountCents)} is more than ${orderId} can give back`,
    );
  }
  payments.markRefunded(orderId, amountCents);
  const entry = refundStore.record({ orderId, amountCents, lines: shares, reason });
  ledger.post({ orderId, kind: "refund", amountCents, memo: reason });
  try {
    notify.send(order.customer, `${money.format(amountCents)} is on its way back to you`);
  } catch (error) {
    if (error.message !== "mailer unavailable") {
      throw error;
    }
  }
  return entry;
}

module.exports = { refund };
