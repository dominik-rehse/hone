const test = require("node:test");
const assert = require("node:assert");
const app = require("../src/app.js");
const orders = require("../src/orders.js");
const payments = require("../src/payments.js");
const ledger = require("../src/ledger.js");
const refundStore = require("../src/refund-store.js");
const notify = require("../src/notify.js");
const webhook = require("../src/webhook.js");

const lines = [{ sku: "mug", title: "Enamel mug", quantity: 2, unitCents: 1500 }];

function paidOrder() {
  const order = orders.create({ customer: "ada@example.invalid", lines });
  payments.capture(order.id, orders.orderTotal(order));
  return order;
}

test("the receiver knows the provider's refund event", () => {
  app.reset();
  assert.strictEqual(webhook.handles("refund.succeeded"), true);
});

test("takes a refund the provider settled", () => {
  app.reset();
  const order = paidOrder();
  const answer = webhook.receive({
    id: "evt_r1",
    type: "refund.succeeded",
    data: { orderId: order.id, amountCents: 1200, reason: "dispute" },
  });
  assert.strictEqual(answer.ok, true);
  assert.strictEqual(refundStore.refundedTotal(order.id), 1200);
  assert.strictEqual(ledger.totalOf(order.id, "refund"), 1200);
  assert.strictEqual(payments.paymentFor(order.id).refundedCents, 1200);
});

test("tells the customer about a refund the provider settled", () => {
  app.reset();
  const order = paidOrder();
  webhook.receive({
    id: "evt_r2",
    type: "refund.succeeded",
    data: { orderId: order.id, amountCents: 1200 },
  });
  assert.strictEqual(notify.all().length, 1);
  assert.match(notify.all()[0].subject, /back on your card|back to your card/);
});

test("puts the provider's own reason on the entry when the event has none", () => {
  app.reset();
  const order = paidOrder();
  webhook.receive({
    id: "evt_r3",
    type: "refund.succeeded",
    data: { orderId: order.id, amountCents: 1200 },
  });
  assert.strictEqual(refundStore.refundsFor(order.id)[0].reason, "settled by the provider");
});

test("takes a refund the provider settled before the payment reached us", () => {
  app.reset();
  const order = orders.create({ customer: "ada@example.invalid", lines });
  webhook.receive({
    id: "evt_r4",
    type: "refund.succeeded",
    data: { orderId: order.id, amountCents: 1200 },
  });
  assert.strictEqual(refundStore.refundedTotal(order.id), 1200);
  assert.strictEqual(ledger.totalOf(order.id, "refund"), 1200);
  assert.strictEqual(payments.paymentFor(order.id), null);
});
