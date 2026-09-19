const test = require("node:test");
const assert = require("node:assert");
const app = require("../src/app.js");
const orders = require("../src/orders.js");
const payments = require("../src/payments.js");
const ledger = require("../src/ledger.js");
const refundStore = require("../src/refund-store.js");
const { refundWhole } = require("../src/full-refund.js");

const lines = [
  { sku: "mug", title: "Enamel mug", quantity: 2, unitCents: 1500 },
  { sku: "pot", title: "Coffee pot", quantity: 1, unitCents: 2000 },
];

function paidOrder(discountCents = 0) {
  const order = orders.create({ customer: "ada@example.invalid", lines, discountCents });
  payments.capture(order.id, orders.orderTotal(order));
  return order;
}

test("gives a whole order back", () => {
  app.reset();
  const order = paidOrder();
  const entry = refundWhole(order.id, "wrong colour");
  assert.strictEqual(entry.amountCents, 5000);
  assert.deepStrictEqual(
    entry.lines.map((line) => line.amountCents),
    [3000, 2000],
  );
  assert.strictEqual(refundStore.refundedTotal(order.id), 5000);
  assert.strictEqual(ledger.totalOf(order.id, "refund"), 5000);
  assert.strictEqual(payments.paymentFor(order.id).refundedCents, 5000);
});

test("gives a discounted order back at what it was worth", () => {
  app.reset();
  const order = paidOrder(500);
  const entry = refundWhole(order.id, "wrong colour");
  assert.strictEqual(entry.amountCents, 4500);
  assert.strictEqual(
    entry.lines.reduce((total, line) => total + line.amountCents, 0),
    4500,
  );
});

test("turns down an order it has already given back", () => {
  app.reset();
  const order = paidOrder();
  refundWhole(order.id, "wrong colour");
  assert.throws(() => refundWhole(order.id, "wrong colour again"), /back already/);
});

test("turns down an order that is not there", () => {
  app.reset();
  assert.throws(() => refundWhole("o404", "nothing"), /no order/);
});

test("keeps the ledger balance of a paid and refunded order at nothing", () => {
  app.reset();
  const order = paidOrder();
  ledger.post({ orderId: order.id, kind: "payment", amountCents: 5000, memo: "card" });
  refundWhole(order.id, "wrong colour");
  assert.strictEqual(ledger.balance(), 0);
});

test("turns down a ledger entry of a kind it does not know", () => {
  app.reset();
  assert.throws(
    () => ledger.post({ orderId: "o1", kind: "tip", amountCents: 100 }),
    /unknown ledger kind/,
  );
});
