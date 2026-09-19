const test = require("node:test");
const assert = require("node:assert");
const orders = require("../src/orders.js");
const money = require("../src/money.js");
const { pickSkus, refundShares } = require("../src/refund-lines.js");

const lines = [
  { sku: "mug", title: "Enamel mug", quantity: 2, unitCents: 1500 },
  { sku: "pot", title: "Coffee pot", quantity: 1, unitCents: 2000 },
];

function order(discountCents = 0) {
  orders.reset();
  return orders.create({ customer: "ada@example.invalid", lines, discountCents });
}

test("reads an empty pick as the whole order", () => {
  assert.deepStrictEqual(pickSkus(order(), []), ["mug", "pot"]);
  assert.deepStrictEqual(pickSkus(order(), null), ["mug", "pot"]);
  assert.deepStrictEqual(pickSkus(order(), undefined), ["mug", "pot"]);
});

test("keeps the picked skus as they came", () => {
  assert.deepStrictEqual(pickSkus(order(), ["pot"]), ["pot"]);
});

test("turns down a sku the order does not carry", () => {
  assert.throws(() => pickSkus(order(), ["mug", "tin"]), /no line for tin/);
});

test("gives back what a line is worth on an order with no discount", () => {
  assert.deepStrictEqual(refundShares(order(), ["mug"]), [{ sku: "mug", amountCents: 3000 }]);
});

test("takes the order's discount off the lines", () => {
  const o = order(500);
  assert.deepStrictEqual(refundShares(o, ["mug", "pot"]), [
    { sku: "mug", amountCents: 2700 },
    { sku: "pot", amountCents: 1800 },
  ]);
});

test("gives back the whole order at what the order is worth", () => {
  const o = order(500);
  const shares = refundShares(o, ["mug", "pot"]);
  assert.strictEqual(
    money.sum(shares.map((share) => share.amountCents)),
    orders.orderTotal(o),
  );
});

test("gives back nothing for a pick of nothing", () => {
  assert.deepStrictEqual(refundShares(order(), []), []);
});
