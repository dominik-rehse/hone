const orders = require("../orders.js");
const payments = require("../payments.js");
const ledger = require("../ledger.js");
const notify = require("../notify.js");
const seen = require("../seen.js");
const money = require("../money.js");

// `payment.succeeded`: the provider has the customer's money.
function handlePaymentSucceeded(event) {
  if (seen.alreadyHandled(event.id)) {
    return { ok: true, repeat: true };
  }
  const { orderId, amountCents } = event.data;
  payments.capture(orderId, amountCents);
  ledger.post({ orderId, kind: "payment", amountCents, memo: event.id });
  seen.remember(event.id);
  const order = orders.get(orderId);
  if (order !== null) {
    notify.send(order.customer, `We have your payment of ${money.format(amountCents)}`);
  }
  return { ok: true };
}

module.exports = { handlePaymentSucceeded };
