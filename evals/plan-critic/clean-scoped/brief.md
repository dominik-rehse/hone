# Plan under review

## Plan: export/csv-escaping

### What
CSV export currently emits fields verbatim, so a field containing a comma,
double-quote, or newline corrupts the row structure. Escape fields per RFC 4180:
wrap a field in double-quotes when it contains a comma, quote, CR, or LF, and
double any embedded quote.

### Why
A user exporting contacts whose names contain commas ("Doe, Jane") gets a broken
file that re-imports with shifted columns. This is a data-integrity bug reported
by two customers.

### How I'll know it works
A round-trip test: a row with a field containing each of `, " \n \r` serializes,
then a standard CSV parser reads it back byte-for-byte identical to the input
row. Plus a golden-file assertion for a known tricky record.

### Notes for the loop
- Critical path: this is untrusted-input serialization — add a property test
  (parse(serialize(x)) == x over generated fields).
- Touches only src/export/csv.ts. Independent of in-flight work.

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/export-format.md (chose CSV over TSV).
Existing Notes: docs/notes/export.md.
