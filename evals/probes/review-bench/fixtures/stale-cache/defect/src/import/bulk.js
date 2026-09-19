const store = require("../store.js");
const money = require("../money.js");
const { parseCsv } = require("./csv.js");

const COLUMNS = 2;

// One row of the file, read and checked. `ok` says whether it may be written.
function readRow(row) {
  if (row.fields.length !== COLUMNS) {
    return {
      ok: false,
      lineNo: row.lineNo,
      sku: null,
      reason: `${COLUMNS} columns expected, ${row.fields.length} found`,
    };
  }
  const [sku, price] = row.fields;
  if (sku === "") {
    return { ok: false, lineNo: row.lineNo, sku: null, reason: "the sku is empty" };
  }
  if (price === "") {
    return { ok: false, lineNo: row.lineNo, sku, reason: "the price is empty" };
  }
  const cents = money.parseAmount(price);
  if (cents === null) {
    return { ok: false, lineNo: row.lineNo, sku, reason: `"${price}" is not a price` };
  }
  return { ok: true, lineNo: row.lineNo, sku, cents };
}

// Read a supplier file and put the prices it carries on the list. The rows it
// cannot read are reported and the rest are written.
function importPrices(text) {
  let rows;
  try {
    rows = parseCsv(text);
  } catch (err) {
    if (err.code !== "BAD_HEADER") {
      throw err;
    }
    return { read: 0, written: 0, rejected: [{ lineNo: 1, sku: null, reason: err.message }] };
  }
  const accepted = [];
  const rejected = [];
  const seen = new Set();
  for (const row of rows) {
    const read = readRow(row);
    if (!read.ok) {
      rejected.push(read);
      continue;
    }
    if (seen.has(read.sku)) {
      rejected.push({
        ok: false,
        lineNo: read.lineNo,
        sku: read.sku,
        reason: "the file carries this sku twice",
      });
      continue;
    }
    seen.add(read.sku);
    accepted.push([read.sku, read.cents]);
  }
  const written = store.setMany(accepted);
  return { read: rows.length, written, rejected };
}

// What the importer prints when it is done: a count, then a line per rejection.
function formatSummary(summary) {
  const head = `read ${summary.read}, wrote ${summary.written}, rejected ${summary.rejected.length}`;
  const lines = summary.rejected.map(
    (row) => `  line ${row.lineNo}: ${row.sku == null ? "?" : row.sku} ${row.reason}`,
  );
  return [head, ...lines].join("\n");
}

module.exports = { importPrices, formatSummary, readRow };
