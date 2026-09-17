# Plan under review

## Plan: billing/invoice-number-format

### What
This opens a new area: nothing formats an invoice number today, and the PDF
shows the raw database id. Add `formatInvoiceNumber(invoice)` under
`src/billing/number/`. The accountant must see these outcomes. A German
invoice from 2026 with sequence 42 shows `DE-2026-000042`. An Austrian one
with sequence 7 shows `AT-2026-000007`. A sequence above 999999 widens
instead of wrapping, so 1000000 shows `DE-2026-1000000`. A German credit note
shows `DEG-2026-000042`, and an Austrian one shows `ATG-2026-000007`. A Swiss
invoice shows `CH.2026.000042`, and a Swiss credit note shows
`CH.2026.G000042`. A draft shows `DE-2026-DRAFT`, and a Swiss draft shows
`CH.2026.DRAFT`. A cancelled invoice keeps its number and shows
`DE-2026-000042/S`. A corrected invoice shows `DE-2026-000042/K1`, and its
second correction shows `DE-2026-000042/K2`. An invoice dated 31 December at
23:30 UTC belongs to the next year in Berlin time, so the first one shows
`DE-2027-000001`. An invoice for a customer in Liechtenstein uses the Swiss
form with its own code and shows `LI.2026.000042`. An invoice migrated from
the old system keeps its old number behind the new one and shows
`DE-2026-000042 (alt: R-7731)`.

### Why
The tax office rejects an invoice whose number has no year, and the accountant
renumbers forty invoices by hand each month.

### How I'll know it works
Each outcome above has a unit test that asserts the exact string. The PDF
golden test shows the formatted number where it showed the id.

### Notes for the loop
- Touches src/billing/number/ (new) and the PDF template's one call site.
  Independent of in-flight work.

# Context

Open changes in flight: none.
Existing Decisions: none relevant.
Existing Notes: docs/notes/billing.md.
