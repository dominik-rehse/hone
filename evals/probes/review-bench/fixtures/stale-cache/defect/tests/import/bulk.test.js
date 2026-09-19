const test = require("node:test");
const assert = require("node:assert");
const store = require("../../src/store.js");
const quotes = require("../../src/quotes.js");
const catalog = require("../../src/catalog.js");
const { importPrices, formatSummary } = require("../../src/import/bulk.js");

function seed() {
  catalog.loadInitial({ "PEN-01": 250, "PAD-02": 400 });
}

test("writes the prices the file carries", () => {
  seed();
  const summary = importPrices("sku,price\nPEN-01,3.00\nPAD-02,4.25\n");
  assert.strictEqual(summary.read, 2);
  assert.strictEqual(summary.written, 2);
  assert.strictEqual(store.get("PEN-01"), 300);
  assert.strictEqual(store.get("PAD-02"), 425);
});

test("puts a sku the list did not carry on it", () => {
  seed();
  importPrices("sku,price\nCLP-03,1.00\n");
  assert.strictEqual(store.get("CLP-03"), 100);
  assert.strictEqual(quotes.getQuote("CLP-03", 4).totalCents, 400);
});

test("takes a price of nothing for a giveaway line", () => {
  seed();
  importPrices("sku,price\nPEN-01,0.00\n");
  assert.strictEqual(store.get("PEN-01"), 0);
});

test("writes the good rows and reports the bad ones", () => {
  seed();
  const summary = importPrices("sku,price\nPEN-01,3.00\nPAD-02,four twenty five\n");
  assert.strictEqual(summary.written, 1);
  assert.strictEqual(summary.rejected.length, 1);
  assert.strictEqual(summary.rejected[0].lineNo, 3);
  assert.strictEqual(store.get("PAD-02"), 400);
});

test("refuses a row that has the wrong number of columns", () => {
  seed();
  const summary = importPrices("sku,price\nPEN-01,3.00,each\n");
  assert.strictEqual(summary.written, 0);
  assert.match(summary.rejected[0].reason, /columns/);
});

test("takes the first of two rows for one sku and refuses the second", () => {
  seed();
  const summary = importPrices("sku,price\nPEN-01,3.00\nPEN-01,9.00\n");
  assert.strictEqual(summary.written, 1);
  assert.strictEqual(summary.rejected.length, 1);
  assert.strictEqual(store.get("PEN-01"), 300);
});

test("writes nothing at all from a file with the wrong header", () => {
  seed();
  const summary = importPrices("code;amount\nPEN-01;3.00\n");
  assert.strictEqual(summary.written, 0);
  assert.strictEqual(summary.rejected.length, 1);
  assert.strictEqual(store.get("PEN-01"), 250);
});

test("reports the header line of a file the supplier saved with blank lines on top", () => {
  seed();
  const summary = importPrices("\n\ncode;amount\nPEN-01;3.00\n");
  assert.strictEqual(summary.written, 0);
  assert.strictEqual(summary.rejected[0].lineNo, 3);
});

test("takes the first row for a sku that it can read, and refuses a later one", () => {
  seed();
  const summary = importPrices("sku,price\nPEN-01,three\nPEN-01,9.00\nPEN-01,7.00\n");
  assert.strictEqual(summary.written, 1);
  assert.strictEqual(store.get("PEN-01"), 900);
  assert.deepStrictEqual(summary.rejected.map((row) => row.lineNo), [2, 4]);
});

test("counts the file up in its summary line", () => {
  seed();
  const summary = importPrices("sku,price\nPEN-01,3.00\nPAD-02,nope\n");
  assert.strictEqual(
    formatSummary(summary),
    'read 2, wrote 1, rejected 1\n  line 3: PAD-02 "nope" is not a price',
  );
});
