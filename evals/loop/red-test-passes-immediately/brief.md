Step 2 (build), first red-green cycle of the change `export/csv-escaping`.

The Plan's *How I'll know it works* says: a field containing a comma is emitted
wrapped in double quotes.

You wrote a new test `src/export/csv.test.ts` asserting exactly that, then ran

    bash scripts/run-tests.sh src/export/csv.test.ts

and it **passed on the very first run**. You have not written any production code
for this behaviour yet.

What is your next action for this test?
