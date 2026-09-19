const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const { minuteClock, START, MINUTE } = require("./clock.js");

function fresh() {
  store.reset(minuteClock());
}

test("gives every ticket its own id and keeps it open", () => {
  fresh();
  const one = store.add({ subject: "Password reset", requester: "ann" });
  const two = store.add({ subject: "Card declined", requester: "bo" });
  assert.notStrictEqual(one.id, two.id);
  assert.strictEqual(one.status, "open");
  assert.strictEqual(one.priority, "normal");
  assert.strictEqual(one.assignee, null);
});

test("stamps each ticket with the time it took it", () => {
  fresh();
  const one = store.add({ subject: "Password reset", requester: "ann" });
  const two = store.add({ subject: "Card declined", requester: "bo" });
  assert.strictEqual(one.createdAt, START);
  assert.strictEqual(two.createdAt, START + MINUTE);
});

test("hands back the tickets it was given", () => {
  fresh();
  store.add({ subject: "first", requester: "ann" });
  store.add({ subject: "second", requester: "bo" });
  store.add({ subject: "third", requester: "cy" });
  assert.deepStrictEqual(
    store.all().map((ticket) => ticket.subject),
    ["first", "second", "third"],
  );
});

test("finds a ticket by its id, and nothing for an unknown one", () => {
  fresh();
  const one = store.add({ subject: "Site down", requester: "cy" });
  assert.strictEqual(store.get(one.id).subject, "Site down");
  assert.strictEqual(store.get(999), null);
});

test("assigns, closes and repriorities a ticket", () => {
  fresh();
  const one = store.add({ subject: "Invoice wrong", requester: "di" });
  assert.strictEqual(store.assign(one.id, "mel").assignee, "mel");
  assert.strictEqual(store.setPriority(one.id, "urgent").priority, "urgent");
  const closed = store.close(one.id);
  assert.strictEqual(closed.status, "closed");
  assert.ok(closed.closedAt > closed.createdAt);
  assert.strictEqual(store.isOpen(closed), false);
});

test("answers nothing when the id is not there", () => {
  fresh();
  assert.strictEqual(store.assign(1, "mel"), null);
  assert.strictEqual(store.close(1), null);
  assert.strictEqual(store.setPriority(1, "low"), null);
});
