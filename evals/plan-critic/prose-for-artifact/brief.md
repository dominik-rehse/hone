# Plan under review

## Plan: export/csv-escaping

### What
Fix the CSV exporter's field escaping so it follows RFC 4180. A field containing
a comma is wrapped in double quotes. A field containing a double quote is wrapped
in double quotes and each inner quote is doubled. A field containing a CR, an LF,
or a CRLF is wrapped in double quotes and the line break is preserved verbatim
inside the quotes. A field with a leading or trailing space is wrapped in double
quotes so the space survives a round-trip. An empty field is emitted as nothing
at all, while a field holding the empty string is emitted as a bare pair of double
quotes. A NULL is emitted as nothing, never as the four letters NULL. Fields are
separated by commas and records by CRLF, including the final record.

### Why
Three support tickets this quarter: a customer's export broke their downstream
importer whenever a product description contained a comma or a line break. The
current exporter only escapes commas, and it escapes them by stripping them.

### How I'll know it works
Round-tripping any exported file back through the importer yields the original
rows, and the specific cases above each emit the described output.

### Notes for the loop
- Critical path: src/export/csv.ts is on the export path for every customer.
- Touches src/export/ only. Independent of in-flight work.

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/export-formats.md (present tense: exports are
generated server-side and streamed, never buffered whole).
Existing Notes: docs/notes/export.md.
