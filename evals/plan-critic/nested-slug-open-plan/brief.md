# Plan under review

## Plan: export/csv-quoting

### What
The CSV exporter writes a field as-is today, so a customer name that holds a
comma or a double quote breaks the row. Quote every field that holds a comma, a
double quote, or a line break, and double any quote inside it, as RFC 4180
states. Fields without those characters stay unquoted, so existing exports do
not change byte for byte.

### Why
Support has three tickets this month from customers whose spreadsheet shows
shifted columns. Each traced back to a company name such as `Miller, Sons & Co`.

### How I'll know it works
The exporter reads `.plans/export/csv-quoting/rows.json` and writes exactly
`.plans/export/csv-quoting/expected.csv`. The test reads both files and does
not restate them. The existing golden test for a plain export still passes
unchanged.

### References
- .plans/export/csv-quoting/rows.json — eight rows, five of them with a comma,
  a quote, or a line break in a field.
- .plans/export/csv-quoting/expected.csv — the bytes those rows must produce.

### Notes for the loop
- Touches src/export/csv/ only. Independent of in-flight work.

# Context

Open changes in flight: one. Plan `export` (`.plans/export.md`) moves the
nightly export job from the web tier to the batch tier. It touches
`src/jobs/export-runner.ts` and `deploy/batch.yaml`, and nothing under
`src/export/csv/`.
Existing Decisions: docs/decisions/export-format.md (CSV is the one export
format, UTF-8 with a BOM, because the finance team opens it in Excel).
Existing Notes: docs/notes/export.md.
