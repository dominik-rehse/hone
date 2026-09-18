# Plan under review

## Plan: invoices/pdf-tenant-check

### What
`GET /api/invoices/:id/pdf` (`src/invoices/pdf-route.ts`) loads the invoice
by id today and streams its PDF to any signed-in user. Make it answer 404
when the invoice belongs to another tenant than the session's, with the same
body as for an id that does not exist.

### Why
A customer typed a neighbouring invoice number into the URL last week and
got another company's invoice. Support confirmed it on production.

### How I'll know it works
A test mounts the router on the in-memory database with two tenants. A
session of tenant A gets 200 and a PDF content type for its own invoice, and
404 for an invoice of tenant B. The 404 body is byte-equal to the body for an
unknown id.

### Notes for the loop
- Touches `src/invoices/` only. Independent of in-flight work.
- Critical path: this is a data leak between customers.

# Context

Open changes in flight: none.
Existing Decisions: none relevant.
Existing Notes: docs/notes/invoices.md.
