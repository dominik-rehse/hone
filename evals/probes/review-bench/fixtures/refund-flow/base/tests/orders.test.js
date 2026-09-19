const test = require("node:test");
const assert = require("node:assert");
const orders = require("../src/orders.js");

const lines = [
  { sku: "mug", title: "Enamel mug", quantity: 2, unitCents: 1500 },
  { sku: "pot", title: "Coffee pot", quantity: 1, unitCents: 2000 },
];

test("takes an order and gives it an id", () => {
  orders.reset();
  const order = orders.create({ customer: "ada@example.invalid", lines });
  assert.strictEqual(order.id, "o1");
  assert.strictEqual(orders.get("o1").customer, "ada@example.invalid");
  assert.strictEqual(orders.get("nope"), null);
});

test("keeps its own copy of the lines", () => {
  orders.reset();
  const order = orders.create({ customer: "ada@example.invalid", lines });
  order.lines[0].quantity = 9;
  assert.strictEqual(lines[0].quantity, 2);
});

test("totals the lines and takes the discount off", () => {
  orders.reset();
  const order = orders.create({
    customer: "ada@example.invalid",
    lines,
    discountCents: 500,
  });
  assert.strictEqual(orders.lineTotal(order.lines[0]), 3000);
  assert.strictEqual(orders.orderTotal(order), 4500);
});

test("spreads the discount over the lines", () => {
  orders.reset();
  const order = orders.create({
    customer: "ada@example.invalid",
    lines,
    discountCents: 500,
  });
  const net = orders.discountedLineTotals(order);
  assert.deepStrictEqual(net, [2700, 1800]);
  assert.strictEqual(net[0] + net[1], orders.orderTotal(order));
});

test("finds a line by its sku", () => {
  orders.reset();
  const order = orders.create({ customer: "ada@example.invalid", lines });
  assert.strictEqual(orders.lineOf(order, "pot").unitCents, 2000);
  assert.strictEqual(orders.lineOf(order, "tin"), null);
});
