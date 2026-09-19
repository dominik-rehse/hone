const orders = require("../orders.js");
const payments = require("../payments.js");
const ledger = require("../ledger.js");
const refundStore = require("../refund-store.js");
const notify = require("../notify.js");
const seen = require("../seen.js");
const money = require("../money.js");

// `refund.succeeded`: money has gone back on the customer's card. The provider
// settles some refunds itself, after a dispute, and this event is the first the
// shop hears of one of those.
function handleRefundSucceeded(event) {
  if (seen.alreadyHandled(event.id)) {
    return { ok: true, repeat: true };
  }
  const { orderId, amountCents, reason = "settled by the provider" } = event.data;
  if (payments.paymentFor(orderId) !== null) {
    payments.markRefunded(orderId, amountCents);
  }
  refundStore.record({ orderId, amountCents, reason });
  ledger.post({ orderId, kind: "refund", amountCents, memo: event.id });
  seen.remember(event.id);
  const order = orders.get(orderId);
  if (order !== null) {
    notify.send(order.customer, `${money.format(amountCents)} has gone back to your card`);
  }
  return { ok: true };
}

module.exports = { handleRefundSucceeded };
