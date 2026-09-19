const test = require("node:test");
const assert = require("node:assert");
const { toIsoDate } = require("../src/dates.js");
const terms = require("../src/terms.js");

// The due day as the invoice writes it out.
const due = (issuedOn, chosen) => toIsoDate(terms.dueDate(issuedOn, chosen));

test("offers every term the billing form lists", () => {
  assert.deepStrictEqual(terms.TERMS, [
    "on-receipt",
    "net-7",
    "net-14",
    "net-30",
    "end-of-month",
  ]);
});

test("falls due the term's days after the invoice went out", () => {
  assert.strictEqual(due("2026-01-10", "net-30"), "2026-02-09");
  assert.strictEqual(due("2026-01-10", "net-14"), "2026-01-24");
  assert.strictEqual(due("2026-01-10", "net-7"), "2026-01-17");
  assert.strictEqual(due("2026-01-10", "on-receipt"), "2026-01-10");
});

test("falls due in the month it went out in, on end-of-month terms", () => {
  assert.ok(due("2026-01-10", "end-of-month").startsWith("2026-01"));
  assert.ok(due("2026-04-02", "end-of-month").startsWith("2026-04"));
  assert.ok(due("2026-02-11", "end-of-month").startsWith("2026-02"));
  assert.ok(due("2028-02-11", "end-of-month").startsWith("2028-02"));
});

test("gives every invoice of one month the same end-of-month day", () => {
  assert.strictEqual(
    due("2026-03-01", "end-of-month"),
    due("2026-03-30", "end-of-month"),
  );
});

test("gives an invoice of the 10th longer than one paid on receipt", () => {
  assert.ok(due("2026-01-10", "end-of-month") > due("2026-01-10", "on-receipt"));
});

test("falls back on the usual terms when the invoice names none", () => {
  assert.strictEqual(due("2026-01-10", null), due("2026-01-10", terms.DEFAULT_TERMS));
  assert.strictEqual(due("2026-01-10", undefined), "2026-02-09");
});

test("refuses terms the module has no rule for", () => {
  assert.throws(() => terms.dueDate("2026-01-10", "net-45"), /unknown payment terms/);
});

test("names each term the way the form does", () => {
  assert.strictEqual(terms.labelFor("net-30"), "within 30 days");
  assert.strictEqual(terms.labelFor("end-of-month"), "end of month");
  assert.strictEqual(terms.labelFor(null), "within 30 days");
  assert.strictEqual(terms.labelFor("whatever"), "whatever");
});
