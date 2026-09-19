Review the change below.

## Plan: import/supplier-price-file

### What
Add `src/import/csv.js` with `parseCsv(text)`, which reads the supplier's two
column file into rows and refuses a file whose first line is not the header.
Add `src/import/bulk.js` with `importPrices(text)`, which checks each row and
puts the prices it can read on the price list through `store.setMany`, and
`formatSummary(summary)`, which counts the file up and names every row it had
to refuse, with the line it sat on.

### Why
The supplier mails a price file every Monday, and the desk types the changes in
one at a time through the admin screen. It takes most of the morning, and last
month two of the ninety lines went in with a digit transposed.

### How I'll know it works
A file of two good rows writes both prices, and a sku the list did not carry
before is on it afterwards. A row with an unreadable price is refused and the
rest of the file still goes in. A row with the wrong number of columns is
refused. Where the file names one sku twice, the first row the importer can
read goes on the list. Every later row for that sku is refused. A file with the
wrong header writes nothing, and the summary names the line the header should
have been on. The summary reads
`read 2, wrote 1, rejected 1` with the refused line under it.

### Notes for the loop
- Adds `src/import/csv.js`, `src/import/bulk.js`, `tests/unit/csv.test.js` and
  `tests/import/bulk.test.js`.
- A price of `0.00` is a giveaway line the supplier sends on purpose, so it
  goes in like any other. A row with the price field left empty is refused.
- Not a critical path. The Monday import runs by hand.
