const test = require("node:test");
const assert = require("node:assert");
const { createInvoice } = require("../src/invoice.js");
const render = require("../src/render.js");

function sample(extra = {}) {
  return createInvoice({
    id: "2026-0041",
    customer: "Nordwind GmbH",
    issuedOn: "2026-01-08",
    lines: [
      { name: "Consulting", quantity: 2, unitCents: 45000 },
      { name: "Travel", quantity: 1, unitCents: 12750 },
    ],
    ...extra,
  });
}

test("writes one body line per invoice line", () => {
  assert.strictEqual(
    render.renderLine({ name: "Consulting", quantity: 2, unitCents: 45000 }),
    "    2 x Consulting  900.00 EUR",
  );
});

test("writes the head, the body and the totals", () => {
  assert.strictEqual(
    render.renderInvoice(sample()),
    [
      "Invoice 2026-0041",
      "To      Nordwind GmbH",
      "Issued  2026-01-08",
      "",
      "    2 x Consulting  900.00 EUR",
      "    1 x Travel  127.50 EUR",
      "",
      "Net     1027.50 EUR",
      "VAT     195.23 EUR",
      "Total   1222.73 EUR",
    ].join("\n"),
  );
});

test("writes an invoice with no lines as its head and its totals", () => {
  const text = render.renderInvoice(sample({ lines: [] }));
  assert.ok(text.includes("Total   0.00 EUR"));
});

test("writes the collections line with how long it has been over", () => {
  assert.strictEqual(
    render.renderReminderLine(sample(), "2026-02-20"),
    "2026-0041  Nordwind GmbH  1222.73 EUR  13 days over",
  );
});

test("says so in the collections line when nothing is due yet", () => {
  assert.ok(render.renderReminderLine(sample(), "2026-01-20").endsWith("not yet due"));
});
