const test = require("node:test");
const assert = require("node:assert");
const store = require("../src/store.js");
const queue = require("../src/queue.js");
const { minuteClock } = require("./clock.js");

function seed() {
  store.reset(minuteClock());
  return [
    store.add({ subject: "Password reset", requester: "ann", priority: "low" }),
    store.add({ subject: "Card declined", requester: "bo", priority: "normal" }),
    store.add({ subject: "Site down", requester: "cy", priority: "urgent" }),
  ];
}

test("serves the ticket that has waited longest", () => {
  const [ann] = seed();
  assert.strictEqual(queue.nextInQueue().id, ann.id);
});

test("skips a closed ticket", () => {
  const [ann, bo] = seed();
  store.close(ann.id);
  assert.strictEqual(queue.nextInQueue().id, bo.id);
});

test("has nothing to serve on an empty desk", () => {
  store.reset(minuteClock());
  assert.strictEqual(queue.nextInQueue(), null);
  assert.strictEqual(queue.queueDepth(), 0);
});

test("counts the open tickets", () => {
  const [ann] = seed();
  assert.strictEqual(queue.queueDepth(), 3);
  store.close(ann.id);
  assert.strictEqual(queue.queueDepth(), 2);
});

test("hands the next ticket to an agent", () => {
  const [ann] = seed();
  const given = queue.assignNext("mel");
  assert.strictEqual(given.id, ann.id);
  assert.strictEqual(given.assignee, "mel");
  assert.deepStrictEqual(
    queue.assignedTo("mel").map((ticket) => ticket.id),
    [ann.id],
  );
});

test("hands nothing out on an empty desk", () => {
  store.reset(minuteClock());
  assert.strictEqual(queue.assignNext("mel"), null);
  assert.deepStrictEqual(queue.assignedTo("mel"), []);
});
