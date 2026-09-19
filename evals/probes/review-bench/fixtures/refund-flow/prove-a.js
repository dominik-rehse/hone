// Prove that the first planted defect bites. Run it with a seeded repository
// as the working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove-a.js
//
// It exits 0 when the shop cannot give back more than an order is worth over
// two refunds of it, and non-zero when it can. So it must pass on the `clean`
// variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const app = load("src/app.js");
const orders = load("src/orders.js");
const payments = load("src/payments.js");
const refundStore = load("src/refund-store.js");
const webhook = load("src/webhook.js");
const { refund } = load("src/refund.js");

app.reset();
const order = orders.create({
  customer: "ada@example.invalid",
  lines: [
    { sku: "mug", title: "Enamel mug", quantity: 2, unitCents: 1500 },
    { sku: "pot", title: "Coffee pot", quantity: 1, unitCents: 2000 },
  ],
});
payments.capture(order.id, orders.orderTotal(order));

// The customer disputes the order and the provider settles 30.00 of it.
webhook.receive({
  id: "evt_r7",
  type: "refund.succeeded",
  data: { orderId: order.id, amountCents: 3000, reason: "dispute" },
});
assert.strictEqual(refundStore.refundedTotal(order.id), 3000);

// A week later support gives the mug line back as well.
assert.throws(
  () => refund(order.id, ["mug"], "arrived broken"),
  /more than/,
  "a refund the order can no longer cover is turned down",
);

assert.ok(
  refundStore.refundedTotal(order.id) <= orders.orderTotal(order),
  `the order has had ${refundStore.refundedTotal(order.id)} back of ${orders.orderTotal(order)}`,
);
