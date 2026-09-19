const money = require("./money.js");

// What the payment provider has taken for an order, and what of it has gone
// back to the customer.

const captures = [];

function capture(orderId, amountCents) {
  const payment = { orderId, amountCents, refundedCents: 0, at: Date.now() };
  captures.push(payment);
  return payment;
}

function paymentFor(orderId) {
  return captures.find((payment) => payment.orderId === orderId) ?? null;
}

function capturedTotal(orderId) {
  return money.sum(
    captures.filter((payment) => payment.orderId === orderId).map((p) => p.amountCents),
  );
}

// Note on the order's payment that `amountCents` went back.
function markRefunded(orderId, amountCents) {
  const payment = paymentFor(orderId);
  if (payment === null) {
    throw new Error(`no payment for ${orderId}`);
  }
  payment.refundedCents += amountCents;
  return payment;
}

function all() {
  return captures.slice();
}

function reset() {
  captures.length = 0;
}

module.exports = { capture, paymentFor, capturedTotal, markRefunded, all, reset };
