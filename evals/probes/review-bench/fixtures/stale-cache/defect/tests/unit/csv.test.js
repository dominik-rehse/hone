const test = require("node:test");
const assert = require("node:assert");
const { parseCsv, CsvError } = require("../../src/import/csv.js");

test("gives one row per line after the header", () => {
  const rows = parseCsv("sku,price\nPEN-01,3.00\nPAD-02,4.25\n");
  assert.strictEqual(rows.length, 2);
  assert.deepStrictEqual(rows[0].fields, ["PEN-01", "3.00"]);
});

test("counts the line a row sat on, blank lines and all", () => {
  const rows = parseCsv("sku,price\n\nPEN-01,3.00\n");
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].lineNo, 3);
});

test("reads a file the supplier saved with a byte order mark in front", () => {
  const rows = parseCsv("\ufeffsku,price\nPEN-01,3.00\n");
  assert.strictEqual(rows.length, 1);
  assert.deepStrictEqual(rows[0].fields, ["PEN-01", "3.00"]);
});

test("trims the spaces around a field", () => {
  const rows = parseCsv("sku, price\n PEN-01 , 3.00 \n");
  assert.deepStrictEqual(rows[0].fields, ["PEN-01", "3.00"]);
});

test("keeps a row with the wrong number of columns", () => {
  const rows = parseCsv("sku,price\nPEN-01,3.00,each\n");
  assert.strictEqual(rows[0].fields.length, 3);
});

test("refuses a file whose first line is not the header", () => {
  assert.throws(() => parseCsv("PEN-01,3.00\n"), CsvError);
  assert.throws(() => parseCsv(""), (err) => err.code === "BAD_HEADER");
});
