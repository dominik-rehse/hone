# The sketch, as the caller gave it

> The CSV importer stops at the first bad row. An operator uploads a
> 5,000-row file, gets one error, fixes that row, uploads again, and gets the
> next one. Yesterday one file took eleven rounds of that. Make a single
> upload enough to see everything that is wrong with the file. An error has to
> name the row number and the column, so the operator can find it in a
> spreadsheet. Touches `src/import/` only, and it is not a critical path.

# Plan under review

## Plan: import/report-every-bad-row

### What
`importRows` today validates a row, writes it, and throws `ImportError` on the
first row that fails, so the rows after it are never read. Validate the whole
file before writing anything instead. `importRows` collects a finding per bad
row (`{ row, column, reason }`), and when the list is not empty it writes
nothing and throws `ImportError` carrying the whole list. A file whose rows
all validate imports exactly as it does today.

### Why
An operator fixing a 5,000-row file re-uploads once per bad row. One file took
eleven rounds yesterday, and each round is a full re-upload and a re-read.

### How I'll know it works
A file with bad rows at 12, 340, and 4,001 throws one `ImportError` whose
findings name rows 12, 340, and 4,001, each with the offending column. Its
`message` carries all three lines, so the upload page shows every one. The
table holds the same count of rows as before the call. A file with no bad row
imports all 5,000 rows, as the current tests already pin.

### Notes for the loop
- Touches `src/import/reader.js` and `src/import/validate.js`. Independent of
  in-flight work.
- Redesign: `importRows` writes as it reads today, and
  `src/import/reader.test.js` pins that the throw names the first bad row
  alone. Replace that test. The upload page shows `err.message` and nothing
  else, so the message has to carry every finding. `ImportError` keeps its
  name and its type, and the page needs no change.
- Preserve: the finding shape reuses the field names that `validate.js`
  already returns.

# Context

Open changes in flight: none.

Existing Decisions: `docs/decisions/import-atomicity.md` records that an
import is all or nothing. A file with one bad row writes no row at all,
because a half-imported file left support unable to say what the operator
had loaded. It also records that the importer validates a row against the
same schema module the API uses.

Existing Notes: `docs/notes/import.md`. Its map names `reader.js`,
`validate.js`, and `writer.js`. Its one invariant is that a row reaches
`writer.js` only after `validate.js` has passed it.
