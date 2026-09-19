const test = require("node:test");
const assert = require("node:assert");
const format = require("../../src/format.js");

const t0 = 1_700_000_000_000;
const MINUTE = 60 * 1000;
const ticket = (extra = {}) => ({
  id: 7,
  subject: "Site down",
  requester: "cy",
  priority: "urgent",
  createdAt: t0,
  status: "open",
  assignee: null,
  closedAt: null,
  ...extra,
});

test("reads minutes under an hour as minutes", () => {
  assert.strictEqual(format.formatMinutes(20), "20m");
  assert.strictEqual(format.formatMinutes(0), "0m");
});

test("reads a longer wait as hours and minutes", () => {
  assert.strictEqual(format.formatMinutes(125), "2h 5m");
  assert.strictEqual(format.formatMinutes(120), "2h 0m");
});

test("puts a ticket on one line", () => {
  assert.strictEqual(
    format.formatTicket(ticket()),
    "#7 [urgent] Site down (open, unassigned)",
  );
  assert.strictEqual(
    format.formatTicket(ticket({ assignee: "mel", status: "closed" })),
    "#7 [urgent] Site down (closed, mel)",
  );
});

test("shows the time left on a queue line", () => {
  assert.strictEqual(
    format.formatQueueLine(ticket(), t0 + 10 * MINUTE),
    "#7 urgent 20m left  Site down",
  );
});

test("shows a passed target as time over", () => {
  assert.strictEqual(
    format.formatQueueLine(ticket(), t0 + 100 * MINUTE),
    "#7 urgent 1h 10m over  Site down",
  );
});
