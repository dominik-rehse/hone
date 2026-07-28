# Plan under review

## Plan: import/vendor-price-list

### What
Parse the vendor's monthly price-list file into `PriceRow` records. The format
is fixed by the vendor (a header line, then semicolon-separated rows with a
locale-specific decimal comma); its exact shape is pinned by the reference
files below rather than described here.

### Why
Purchasing re-keys the monthly price list by hand today; two transposition
errors reached production pricing last quarter.

### How I'll know it works
The parser reads `.plans/import/vendor-price-list/sample.csv` and produces
exactly the rows in `.plans/import/vendor-price-list/expected.json`; the test
reads both files rather than restating their contents. A malformed row fails
with an error naming the line number.

### References
- .plans/import/vendor-price-list/sample.csv — a real (anonymized) vendor file.
- .plans/import/vendor-price-list/expected.json — the rows it must parse to.

### Notes for the loop
- Touches src/import/ only. Independent of in-flight work.

# Context

Open changes in flight: none.
Existing Decisions: none relevant.
Existing Notes: docs/notes/import.md.
