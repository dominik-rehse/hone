const test = require("node:test");
const assert = require("node:assert");
const app = require("../src/app.js");
const orders = require("../src/orders.js");
const payments = require("../src/payments.js");
const ledger = require("../src/ledger.js");
const notify = require("../src/notify.js");
const webhook = require("../src/webhook.js");

const lines = [{ sku: "mug", title: "Enamel mug", quantity: 2, unitCents: 1500 }];

function paidOrder() {
  const order = orders.create({ customer: "ada@example.invalid", lines });
  return order;
}

test("answers an event type nothing is registered for", () => {
  app.reset();
  assert.deepStrictEqual(webhook.receive({ id: "evt_0", type: "card.expired", data: {} }), {
    ok: false,
    reason: "unhandled",
  });
});

test("takes a payment event and writes it down", () => {
  app.reset();
  const order = paidOrder();
  webhook.receive({
    id: "evt_1",
    type: "payment.succeeded",
    data: { orderId: order.id, amountCents: 3000 },
  });
  assert.strictEqual(payments.capturedTotal(order.id), 3000);
  assert.strictEqual(ledger.totalOf(order.id, "payment"), 3000);
  assert.strictEqual(notify.all().length, 1);
});

test("takes the same payment event as it comes round again", () => {
  app.reset();
  const order = paidOrder();
  const event = {
    id: "evt_2",
    type: "payment.succeeded",
    data: { orderId: order.id, amountCents: 3000 },
  };
  webhook.receive(event);
  const second = webhook.receive(event);
  assert.strictEqual(second.repeat, true);
  assert.strictEqual(payments.capturedTotal(order.id), 3000);
});

test("works a payment event through while the mailer is down", () => {
  app.reset();
  const order = paidOrder();
  notify.takeDown(1);
  webhook.receive({
    id: "evt_3",
    type: "payment.succeeded",
    data: { orderId: order.id, amountCents: 3000 },
  });
  assert.strictEqual(payments.capturedTotal(order.id), 3000);
  assert.strictEqual(ledger.totalOf(order.id, "payment"), 3000);
  assert.strictEqual(notify.pending().length, 1);
  notify.deliverPending();
  assert.strictEqual(notify.pending().length, 0);
});

test("runs the handler again for the attempt that went wrong", () => {
  app.reset();
  const order = paidOrder();
  notify.takeDown(1);
  webhook.receive({
    id: "evt_4",
    type: "payment.succeeded",
    data: { orderId: order.id, amountCents: 3000 },
  });
  assert.strictEqual(webhook.attemptLog().filter((a) => a.id === "evt_4").length, 2);
});
