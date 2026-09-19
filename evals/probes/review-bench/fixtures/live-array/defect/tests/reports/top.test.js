const test = require("node:test");
const assert = require("node:assert");
const store = require("../../src/store.js");
const { minuteClock } = require("../clock.js");
const { topByAge, topByPriority } = require("../../src/reports/top.js");

function seed() {
  store.reset(minuteClock());
  return [
    store.add({ subject: "Password reset", requester: "ann", priority: "low" }),
    store.add({ subject: "Card declined", requester: "bo", priority: "normal" }),
    store.add({ subject: "Site down", requester: "cy", priority: "urgent" }),
    store.add({ subject: "Invoice wrong", requester: "di", priority: "high" }),
  ];
}

test("lists the tickets that have waited longest", () => {
  const [ann, bo] = seed();
  assert.deepStrictEqual(
    topByAge(2).map((ticket) => ticket.id),
    [ann.id, bo.id],
  );
});

test("lists the most urgent tickets first", () => {
  const [, , cy, di] = seed();
  assert.deepStrictEqual(
    topByPriority(2).map((ticket) => ticket.id),
    [cy.id, di.id],
  );
});

test("leaves a closed ticket out of both lists", () => {
  const [ann] = seed();
  store.close(ann.id);
  assert.ok(!topByAge(4).some((ticket) => ticket.id === ann.id));
  assert.ok(!topByPriority(4).some((ticket) => ticket.id === ann.id));
});

test("gives what there is when asked for more", () => {
  seed();
  assert.strictEqual(topByAge(10).length, 4);
  assert.strictEqual(topByPriority(10).length, 4);
});

test("gives empty lists on an empty desk", () => {
  store.reset(minuteClock());
  assert.deepStrictEqual(topByAge(3), []);
  assert.deepStrictEqual(topByPriority(3), []);
});
