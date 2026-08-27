# Plan under review

## Plan: billing/amounts-in-cents

### What
`invoices.amount` is a `REAL` column today, and every read path multiplies it by
100 and rounds. Three call sites round in slightly different ways, so a total
built from line items can differ from the stored invoice total by a cent. Store
the amount as an `INTEGER` count of cents instead, and drop the rounding from
the read paths. `formatAmount` keeps its current signature and its output for
every amount the API returns today.

### Why
Support has filed nine tickets this quarter about an invoice whose line items do
not sum to its total. Each one is a rounding disagreement, not a pricing bug.
The float column is the common cause, and the finance export inherits it.

### Why now
The finance export goes to an external auditor from October, so the cent
disagreement stops being a support annoyance and starts being an audit finding.

### How I'll know it works
`docs/../.plans/billing/amounts-in-cents/rounding-cases.md` holds 40 rows of
`stored value → expected cents → expected formatted string`, taken from the nine
support tickets and from the boundaries around `x.005`. The suite reads that
file. A line-item total and its invoice total agree to the cent for all 40. The
three read paths lose their rounding calls, and `grep -r 'Math.round' src/billing/`
returns nothing.

### Notes for the loop
- Touches `src/billing/invoice.ts`, `src/billing/export.ts`, and
  `src/billing/format.ts`, plus the schema.
- Critical path: the export feeds an external auditor. Worth a mutation check.
- `formatAmount`'s output is behaviour this change preserves, and
  `format.test.ts` already pins it.
- Independent of in-flight work.

### References
- `.plans/billing/amounts-in-cents/rounding-cases.md`: the 40 input/expected rows.

# Context

Open changes in flight: none.

Existing Decisions: `docs/decisions/billing-rounding.md`, which records that the
API returns amounts as formatted strings rather than numbers, so that clients
cannot re-round. It says nothing about how the database stores them.

Existing Notes: `docs/notes/billing.md`. Its map names `invoice.ts`,
`export.ts`, and `format.ts`. Its one invariant is that every amount leaving the
billing area goes through `formatAmount`.

The `invoices` table holds 2.3 million rows going back four years.
