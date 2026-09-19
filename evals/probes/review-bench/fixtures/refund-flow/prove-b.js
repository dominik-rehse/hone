// Prove that the second planted defect bites. Run it with a seeded repository
// as the working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove-b.js
//
// It exits 0 when one refund event from the provider puts one refund on the
// books, and non-zero when it puts two there. So it must pass on the `clean`
// variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const app = load("src/app.js");
const orders = load("src/orders.js");
const payments = load("src/payments.js");
const ledger = load("src/ledger.js");
const refundStore = load("src/refund-store.js");
const notify = load("src/notify.js");
const webhook = load("src/webhook.js");

app.reset();
const order = orders.create({
  customer: "ada@example.invalid",
  lines: [{ sku: "mug", title: "Enamel mug", quantity: 2, unitCents: 1500 }],
});
payments.capture(order.id, orders.orderTotal(order));

// The mailer is down for one attempt, which is all it takes for the provider's
// event to be worked through more than once.
notify.takeDown(1);
webhook.receive({
  id: "evt_r9",
  type: "refund.succeeded",
  data: { orderId: order.id, amountCents: 2000, reason: "dispute" },
});

assert.strictEqual(ledger.totalOf(order.id, "refund"), 2000, "one refund reached the ledger");
assert.strictEqual(refundStore.refundedTotal(order.id), 2000, "one refund reached the store");
assert.strictEqual(
  payments.paymentFor(order.id).refundedCents,
  2000,
  "one refund went against the payment",
);
