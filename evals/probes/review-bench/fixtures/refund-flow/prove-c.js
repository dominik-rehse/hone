// Prove that the third planted defect bites. Run it with a seeded repository
// as the working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove-c.js
//
// It exits 0 when what the lines of an order come back at is what the order is
// worth, and non-zero when the two differ. So it must pass on the `clean`
// variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const app = load("src/app.js");
const orders = load("src/orders.js");
const money = load("src/money.js");
const { refundShares } = load("src/refund-lines.js");

app.reset();
// Three lines of the same worth and a discount of one dollar over them.
const order = orders.create({
  customer: "ada@example.invalid",
  lines: [
    { sku: "mug", title: "Enamel mug", quantity: 1, unitCents: 1000 },
    { sku: "pot", title: "Coffee pot", quantity: 1, unitCents: 1000 },
    { sku: "tin", title: "Bean tin", quantity: 1, unitCents: 1000 },
  ],
  discountCents: 100,
});

const shares = refundShares(order, ["mug", "pot", "tin"]);
const back = money.sum(shares.map((share) => share.amountCents));

assert.strictEqual(
  back,
  orders.orderTotal(order),
  `the lines come back at ${back} and the order is worth ${orders.orderTotal(order)}`,
);
