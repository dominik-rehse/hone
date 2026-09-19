Review the change below.

## Plan: invoicing/end-of-month-terms

### What
Move the payment terms out of `src/invoice.js` into `src/terms.js` of their
own. Add one term to them: `end-of-month`. An invoice on that term falls due on
the last day of the month it went out in. `src/terms.js` holds the list the
billing form offers, the name it shows for each term, and `dueDate`.
`createInvoice` refuses a term that is not on the list. It reads an invoice
that names no term as the usual one, which is what `dueDate` does too. The
invoice text grows two lines, the terms and the due day, and the item name gets
a column it is cut to.

### Why
Two thirds of the customers pay on a monthly cycle, and their contracts say
end of month. Billing cuts those invoices on net-30 and then edits the due date
in the PDF by hand. The customer also cannot see the terms anywhere on the
invoice today, which collections gets asked about most weeks.

### How I'll know it works
A net-30 invoice of the 10th falls due on the 9th of the next month. One on
receipt falls due the day it went out. An end-of-month invoice of January falls
due on the 31st, one of April on the 30th, and one of February on the 28th. A
leap year makes that the 29th. Two invoices of one month fall due on one day.
The module turns down a term it has no rule for. The invoice text carries the
terms and the due day. An item name too long for its column ends in three dots.

### Notes for the loop
- Adds `src/terms.js` and `tests/terms.test.js`. Touches `src/invoice.js`,
  `src/render.js` and `tests/render.test.js`.
- `src/overdue.js` reads the due day through `dueOn`, as it does now.
- Not a critical path. Billing reads every invoice before it goes out.
