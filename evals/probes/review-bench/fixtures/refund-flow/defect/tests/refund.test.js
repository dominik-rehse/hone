const test = require("node:test");
const assert = require("node:assert");
const app = require("../src/app.js");
const orders = require("../src/orders.js");
const payments = require("../src/payments.js");
const ledger = require("../src/ledger.js");
const refundStore = require("../src/refund-store.js");
const notify = require("../src/notify.js");
const { refund } = require("../src/refund.js");

const lines = [
  { sku: "mug", title: "Enamel mug", quantity: 2, unitCents: 1500 },
  { sku: "pot", title: "Coffee pot", quantity: 1, unitCents: 2000 },
];

function paidOrder(discountCents = 0) {
  const order = orders.create({ customer: "ada@example.invalid", lines, discountCents });
  payments.capture(order.id, orders.orderTotal(order));
  return order;
}

test("gives one line of an order back", () => {
  app.reset();
  const order = paidOrder();
  const entry = refund(order.id, ["mug"], "arrived broken");
  assert.strictEqual(entry.amountCents, 3000);
  assert.deepStrictEqual(entry.lines, [{ sku: "mug", amountCents: 3000 }]);
  assert.strictEqual(refundStore.refundedTotal(order.id), 3000);
});

test("gives every line back when the caller names none", () => {
  app.reset();
  const order = paidOrder();
  const entry = refund(order.id, [], "the customer changed their mind");
  assert.strictEqual(entry.amountCents, 5000);
  assert.strictEqual(entry.lines.length, 2);
});

test("gives a line of a discounted order back at what it cost", () => {
  app.reset();
  const order = paidOrder(500);
  const entry = refund(order.id, ["mug"], "arrived broken");
  assert.strictEqual(entry.amountCents, 2700);
});

test("writes the refund into the ledger and against the payment", () => {
  app.reset();
  const order = paidOrder();
  refund(order.id, ["pot"], "arrived broken");
  assert.strictEqual(ledger.totalOf(order.id, "refund"), 2000);
  assert.strictEqual(payments.paymentFor(order.id).refundedCents, 2000);
  assert.strictEqual(ledger.balance(), -2000);
});

test("tells the customer what is coming back", () => {
  app.reset();
  const order = paidOrder();
  refund(order.id, ["pot"], "arrived broken");
  assert.strictEqual(notify.all().length, 1);
  assert.match(notify.all()[0].subject, /\$20\.00/);
});

test("gives the money back while the mailer is down", () => {
  app.reset();
  const order = paidOrder();
  notify.takeDown(1);
  const entry = refund(order.id, ["pot"], "arrived broken");
  assert.strictEqual(entry.amountCents, 2000);
  assert.strictEqual(notify.pending().length, 1);
});

test("turns down a sku the order does not carry", () => {
  app.reset();
  const order = paidOrder();
  assert.throws(() => refund(order.id, ["tin"], "arrived broken"), /no line for tin/);
  assert.strictEqual(refundStore.refundsFor(order.id).length, 0);
});

test("turns down an order that is not there", () => {
  app.reset();
  assert.throws(() => refund("o404", ["mug"], "arrived broken"), /no order/);
});
