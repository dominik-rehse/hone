const orders = require("./orders.js");
const payments = require("./payments.js");
const ledger = require("./ledger.js");
const refundStore = require("./refund-store.js");
const notify = require("./notify.js");
const seen = require("./seen.js");
const webhook = require("./webhook.js");
const { handlePaymentSucceeded } = require("./handlers/payment.js");
const { refundWhole } = require("./full-refund.js");

// Put the service together: one handler per event type the provider sends.
function start() {
  webhook.on("payment.succeeded", handlePaymentSucceeded);
  return webhook;
}

// Throw the whole service away and put it back together, which is what the
// suite does between tests.
function reset() {
  orders.reset();
  payments.reset();
  ledger.reset();
  refundStore.reset();
  notify.reset();
  seen.reset();
  webhook.reset();
  start();
}

module.exports = {
  start,
  reset,
  placeOrder: orders.create,
  refundWhole,
};
