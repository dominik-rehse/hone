const test = require("node:test");
const assert = require("node:assert");
const { createInvoice, markPaid } = require("../src/invoice.js");
const overdue = require("../src/overdue.js");

function sample(id, issuedOn, extra = {}) {
  return createInvoice({
    id,
    customer: "Nordwind GmbH",
    issuedOn,
    lines: [{ name: "Consulting", quantity: 1, unitCents: 45000 }],
    ...extra,
  });
}

const january = sample("2026-0041", "2026-01-08");

test("is not overdue on the day it falls due", () => {
  assert.strictEqual(overdue.isOverdue(january, "2026-02-07"), false);
  assert.strictEqual(overdue.daysOverdue(january, "2026-02-07"), 0);
});

test("is overdue the day after", () => {
  assert.strictEqual(overdue.isOverdue(january, "2026-02-08"), true);
  assert.strictEqual(overdue.daysOverdue(january, "2026-02-08"), 1);
});

test("counts the days it has been over", () => {
  assert.strictEqual(overdue.daysOverdue(january, "2026-03-09"), 30);
});

test("is never overdue once it is paid", () => {
  const paid = markPaid(january, "2026-02-03");
  assert.strictEqual(overdue.isOverdue(paid, "2026-06-01"), false);
  assert.strictEqual(overdue.daysOverdue(paid, "2026-06-01"), 0);
});

test("sits in the bucket its age puts it in", () => {
  assert.strictEqual(overdue.agingBucket(january, "2026-02-07"), "current");
  assert.strictEqual(overdue.agingBucket(january, "2026-02-20"), "1-30");
  assert.strictEqual(overdue.agingBucket(january, "2026-03-20"), "31-60");
  assert.strictEqual(overdue.agingBucket(january, "2026-09-01"), "90+");
});

test("lists the overdue invoices, the longest overdue first", () => {
  const older = sample("2026-0002", "2025-11-01");
  const newer = sample("2026-0099", "2026-02-01");
  const notYet = sample("2026-0100", "2026-03-01");
  assert.deepStrictEqual(
    overdue.overdueList([newer, notYet, older, january], "2026-03-09").map((one) => one.id),
    ["2026-0002", "2026-0041", "2026-0099"],
  );
});
