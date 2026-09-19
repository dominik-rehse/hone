const orders = require("./orders.js");
const money = require("./money.js");

// The lines a refund is for. Nothing named means every line of the order, and
// a sku the order does not carry is a mistake the caller must hear about.
function pickSkus(order, skus) {
  if (skus == null || skus.length === 0) {
    return order.lines.map((line) => line.sku);
  }
  for (const sku of skus) {
    if (orders.lineOf(order, sku) === null) {
      throw new Error(`${order.id} has no line for ${sku}`);
    }
  }
  return skus;
}

// What the named lines come back at: each line's own worth, less the part of
// the order's discount that belongs to it.
function refundShares(order, skus) {
  const value = order.lines.map(orders.lineTotal);
  const whole = money.sum(value);
  return order.lines
    .map((line, i) => {
      const part = whole === 0 ? 0 : value[i] / whole;
      const cut = Math.round(part * order.discountCents);
      return { sku: line.sku, amountCents: value[i] - cut };
    })
    .filter((share) => skus.includes(share.sku));
}

module.exports = { pickSkus, refundShares };
