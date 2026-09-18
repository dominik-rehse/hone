# The well-structured outcome, on a TypeScript fixture. Two things are seeded.
# `formatAmount` exists twice, as a private copy in each of two documents, and
# the Plan adds a third document that prints an amount. So the change is the
# third use, where the rule of three says to extract. And the Note states in
# prose that `status` is one of three strings, while the code types it as
# `string`. The Plan adds a fourth status. So the fact is either moved into a
# type, or repeated in prose with one more word in it.
#
# The fixture needs `tsc` on PATH and installs no package. Node strips the
# types when it runs the tests, and `scripts/typecheck.sh` is the only checker.
command -v tsc >/dev/null || { echo "the seeded-structure fixture needs tsc on PATH" >&2; exit 1; }
mkdir -p src/billing docs/notes .plans/billing
cat > package.json <<'EOF'
{
  "name": "lab-fixture",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "scripts": { "test": "node --test" }
}
EOF
cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "strict": true,
    "noEmit": true,
    "allowImportingTsExtensions": true,
    "module": "nodenext",
    "target": "es2022",
    "types": []
  },
  "include": ["src"],
  "exclude": ["src/**/*.test.ts"]
}
EOF
cat > scripts/typecheck.sh <<'SH'
#!/bin/bash
# Type-check adapter. The tests are outside the project, because they import
# `node:test` and the fixture installs no type package for it.
exec tsc --noEmit -p .
SH
chmod +x scripts/typecheck.sh
cat > src/billing/invoice.ts <<'TS'
export type Invoice = { id: string; customer: string; cents: number; status: string };

function formatAmount(cents: number): string {
  return (cents / 100).toFixed(2) + " EUR";
}

export function renderInvoice(invoice: Invoice): string {
  return `Invoice ${invoice.id} for ${invoice.customer}: ${formatAmount(invoice.cents)}`;
}
TS
cat > src/billing/receipt.ts <<'TS'
import type { Invoice } from "./invoice.ts";

function formatAmount(cents: number): string {
  return (cents / 100).toFixed(2) + " EUR";
}

export function renderReceipt(invoice: Invoice, paidOn: string): string {
  return `Receipt for invoice ${invoice.id}: ${formatAmount(invoice.cents)} paid on ${paidOn}`;
}
TS
cat > src/billing/status.ts <<'TS'
import type { Invoice } from "./invoice.ts";

export function markPaid(invoice: Invoice): Invoice {
  if (invoice.status !== "sent") {
    throw new Error(`cannot pay an invoice that is ${invoice.status}`);
  }
  return { ...invoice, status: "paid" };
}
TS
cat > src/billing/invoice.test.ts <<'TS'
import test from "node:test";
import assert from "node:assert";
import { renderInvoice } from "./invoice.ts";

test("prints the amount with two decimals", () => {
  const invoice = { id: "R-7", customer: "Acme", cents: 125000, status: "sent" };
  assert.strictEqual(renderInvoice(invoice), "Invoice R-7 for Acme: 1250.00 EUR");
});
TS
cat > src/billing/receipt.test.ts <<'TS'
import test from "node:test";
import assert from "node:assert";
import { renderReceipt } from "./receipt.ts";

test("prints the amount and the day of payment", () => {
  const invoice = { id: "R-7", customer: "Acme", cents: 990, status: "paid" };
  assert.strictEqual(renderReceipt(invoice, "2026-03-02"), "Receipt for invoice R-7: 9.90 EUR paid on 2026-03-02");
});
TS
cat > src/billing/status.test.ts <<'TS'
import test from "node:test";
import assert from "node:assert";
import { markPaid } from "./status.ts";

test("pays a sent invoice", () => {
  const invoice = { id: "R-7", customer: "Acme", cents: 990, status: "sent" };
  assert.strictEqual(markPaid(invoice).status, "paid");
});

test("refuses to pay a draft", () => {
  const invoice = { id: "R-7", customer: "Acme", cents: 990, status: "draft" };
  assert.throws(() => markPaid(invoice), /cannot pay an invoice that is draft/);
});
TS
cat > docs/notes/billing.md <<'MD'
# billing

Governs: `src/billing/`

Map: `invoice.ts` and `receipt.ts` render the two documents that a customer
gets. `status.ts` moves an invoice through its life.

Invariant: an amount is a whole number of cents until a document prints it.

The `status` of an invoice is one of `draft`, `sent`, and `paid`. Any other
string is a bug, and nothing checks it.
MD
cat > .plans/billing/overdue-reminder.md <<'PLAN'
# Plan: billing/overdue-reminder

## What
An invoice that nobody paid gets a reminder. Add `markOverdue(invoice)` to
`src/billing/status.ts`. It turns a `sent` invoice into an `overdue` one, and
it throws for every other status, in the wording that `markPaid` uses.
`markPaid` accepts an `overdue` invoice as well as a `sent` one. Add
`renderReminder(invoice)` in a new file `src/billing/reminder.ts`. It returns
`Reminder: invoice <id> for <customer> is overdue: <amount>`, with the amount
printed exactly as the invoice prints it.

## Why
Accounting writes each reminder by hand today, 40 to 60 a month, and copies
the amount from the invoice. Two reminders last quarter carried a wrong
amount.

## How I'll know it works
`markOverdue` on a `sent` invoice gives the status `overdue`, and on a
`draft` it throws `cannot mark overdue an invoice that is draft`. `markPaid`
on an `overdue` invoice gives `paid`. `renderReminder` for invoice `R-7` of
`Acme` over 125000 cents gives
`Reminder: invoice R-7 for Acme is overdue: 1250.00 EUR`. Unit tests beside
the code pin the four, and `scripts/typecheck.sh` stays green.

## Notes for the loop
- Touches `src/billing/` only. Independent of in-flight work.
- Not a critical path.
PLAN
