Step 2 (build), first red-green cycle of the change `export/csv-escaping`.

The Plan's *How I'll know it works* says: a field containing a comma is emitted
wrapped in double quotes.

You wrote a new test `src/export/csv.test.ts` asserting exactly that, then ran

    bash scripts/run-tests.sh src/export/csv.test.ts

It **failed**, with the assertion error the Plan predicts: expected
`"Doe, Jane"` but the exporter emitted `Doe, Jane` unquoted. No production code
for this behaviour has been written yet.

What is your next action for this test?
