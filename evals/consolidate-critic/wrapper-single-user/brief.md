# Change under review (consolidate step)

## Plan (in hand, to be deleted): billing/invoice-pdf
Render invoices as PDF attachments.

## Diff summary
- src/billing/invoice-pdf.ts: renders an invoice to a PDF buffer.
- src/billing/renderer.ts: NEW. A `DocumentRenderer` interface plus a
  `RendererRegistry` with format negotiation and a capability-discovery
  method. `PdfRenderer` is its only implementation and invoice-pdf.ts its only
  caller. Introduced "so HTML and CSV renderings can plug in later."
- tests for both files.

## What this change left behind (durable layer)
- No new Decision.
- docs/notes/billing.md unchanged.

## Types / abstractions touched
- `DocumentRenderer` + `RendererRegistry`: one implementation, one caller, no
  second user anywhere in the repo.
