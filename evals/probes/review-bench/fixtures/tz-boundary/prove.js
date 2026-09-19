// Prove that the planted defect bites. Run it with a seeded repository as the
// working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove.js
//
// It runs the invoicing module on a machine that keeps Berlin time, which is
// what the billing host does. It exits 0 when an end-of-month invoice of
// January falls due on the 31st there, and non-zero when it does not. So it
// must pass on the `clean` variant and fail on the `defect` one.
process.env.TZ = "Europe/Berlin";

const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const { createInvoice, dueOn } = load("src/invoice.js");
const { isOverdue } = load("src/overdue.js");

const invoice = createInvoice({
  id: "2026-0041",
  customer: "Nordwind GmbH",
  issuedOn: "2026-01-08",
  terms: "end-of-month",
  lines: [{ name: "Consulting", quantity: 2, unitCents: 45000 }],
});

assert.strictEqual(
  dueOn(invoice),
  "2026-01-31",
  "an end-of-month invoice of January falls due on the last day of January",
);

assert.strictEqual(
  isOverdue(invoice, "2026-01-31"),
  false,
  "collections leaves it alone on the day it falls due",
);
