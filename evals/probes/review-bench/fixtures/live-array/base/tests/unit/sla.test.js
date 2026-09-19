const test = require("node:test");
const assert = require("node:assert");
const sla = require("../../src/sla.js");

const t0 = 1_700_000_000_000;
const ticket = (priority, extra = {}) => ({
  id: 1,
  subject: "Site down",
  priority,
  createdAt: t0,
  status: "open",
  closedAt: null,
  ...extra,
});

test("gives each priority its own target", () => {
  assert.strictEqual(sla.targetMinutes("urgent"), 30);
  assert.strictEqual(sla.targetMinutes("low"), 1440);
});

test("treats an unknown priority as a normal one", () => {
  assert.strictEqual(sla.targetMinutes("platinum"), sla.targetMinutes("normal"));
  assert.strictEqual(sla.rank("platinum"), sla.rank("normal"));
});

test("ranks urgent above high above normal above low", () => {
  assert.ok(sla.rank("urgent") > sla.rank("high"));
  assert.ok(sla.rank("high") > sla.rank("normal"));
  assert.ok(sla.rank("normal") > sla.rank("low"));
});

test("puts the due time one target after the ticket arrived", () => {
  assert.strictEqual(sla.dueAt(ticket("urgent")), t0 + 30 * sla.MINUTE_MS);
});

test("counts the minutes to the target, and past it", () => {
  assert.strictEqual(sla.minutesLeft(ticket("urgent"), t0 + 10 * sla.MINUTE_MS), 20);
  assert.strictEqual(sla.minutesLeft(ticket("urgent"), t0 + 45 * sla.MINUTE_MS), -15);
});

test("calls a ticket breached once its target has passed", () => {
  assert.strictEqual(sla.isBreached(ticket("urgent"), t0 + 10 * sla.MINUTE_MS), false);
  assert.strictEqual(sla.isBreached(ticket("urgent"), t0 + 45 * sla.MINUTE_MS), true);
});

test("judges a closed ticket by when it closed", () => {
  const late = ticket("urgent", { status: "closed", closedAt: t0 + 45 * sla.MINUTE_MS });
  const intime = ticket("urgent", { status: "closed", closedAt: t0 + 10 * sla.MINUTE_MS });
  assert.strictEqual(sla.isBreached(late, t0 + 10 * 86_400_000), true);
  assert.strictEqual(sla.isBreached(intime, t0 + 10 * 86_400_000), false);
});
