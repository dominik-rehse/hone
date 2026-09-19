// Prove that the planted defect bites. Run it with a seeded repository as the
// working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove.js
//
// It exits 0 when an order priced after the supplier file went in is priced at
// the price that file carried, and non-zero when it is priced at the old one.
// So it must pass on the `clean` variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const catalog = load("src/catalog.js");
const quotes = load("src/quotes.js");
const { importPrices } = load("src/import/bulk.js");

catalog.loadInitial({ "PEN-01": 250, "PAD-02": 400 });

assert.strictEqual(
  quotes.getQuote("PEN-01", 4).totalCents,
  1000,
  "four of PEN-01 at 2.50 come to 10.00",
);

const summary = importPrices("sku,price\nPEN-01,5.00\n");
assert.strictEqual(summary.written, 1, "the supplier file wrote one price");

assert.strictEqual(
  quotes.getQuote("PEN-01", 4).totalCents,
  2000,
  "four of PEN-01 come to 20.00 once the supplier file has put it at 5.00",
);
