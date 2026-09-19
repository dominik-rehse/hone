const test = require("node:test");
const assert = require("node:assert");
const invoice = require("../src/invoice.js");

const lines = [
  { name: "Consulting", quantity: 2, unitCents: 45000 },
  { name: "Travel", quantity: 1, unitCents: 12750 },
];

function sample(extra = {}) {
  return invoice.createInvoice({
    id: "2026-0041",
    customer: "Nordwind GmbH",
    issuedOn: "2026-01-08",
    lines,
    ...extra,
  });
}

test("builds an invoice with the usual terms and nothing paid", () => {
  const one = sample();
  assert.strictEqual(one.terms, "net-30");
  assert.strictEqual(one.paidOn, null);
  assert.strictEqual(invoice.isPaid(one), false);
});

test("falls due the term's days after the invoice went out", () => {
  assert.strictEqual(invoice.dueOn(sample()), "2026-02-07");
  assert.strictEqual(invoice.dueOn(sample({ terms: "net-14" })), "2026-01-22");
  assert.strictEqual(invoice.dueOn(sample({ terms: "on-receipt" })), "2026-01-08");
});

test("refuses terms the module has no rule for", () => {
  const odd = { ...sample(), terms: "net-45" };
  assert.throws(() => invoice.dueOn(odd), /unknown payment terms/);
});

test("adds up the lines before tax", () => {
  assert.strictEqual(invoice.netCents(sample()), 102750);
});

test("adds the tax on top", () => {
  assert.strictEqual(invoice.totalCents(sample()), 102750 + 19523);
});

test("has nothing to total on an invoice with no lines", () => {
  const empty = sample({ lines: [] });
  assert.strictEqual(invoice.netCents(empty), 0);
  assert.strictEqual(invoice.totalCents(empty), 0);
});

test("marks an invoice paid without touching the one it came from", () => {
  const one = sample();
  const paid = invoice.markPaid(one, "2026-02-03");
  assert.strictEqual(invoice.isPaid(paid), true);
  assert.strictEqual(paid.paidOn, "2026-02-03");
  assert.strictEqual(invoice.isPaid(one), false);
});
