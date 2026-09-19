const test = require("node:test");
const assert = require("node:assert");
const authz = require("../../src/authz/can.js");
const docs = require("../../src/docs.js");
const users = require("../../src/users.js");

function seed() {
  docs.reset();
  users.reset();
  authz.clear();
  const ada = users.add({ id: "u-ada", name: "Ada", role: "editor" });
  const gus = users.add({ id: "u-gus", name: "Gus", role: "guest" });
  const doc = docs.create({ title: "Q3 plan", ownerId: ada.id });
  return { ada, gus, doc };
}

test("answers from the rules", () => {
  const { ada, gus, doc } = seed();
  assert.strictEqual(authz.can(ada, "edit", doc), true);
  assert.strictEqual(authz.can(gus, "view", doc), false);
});

test("refuses a request with nobody or nothing behind it", () => {
  const { ada, doc } = seed();
  assert.strictEqual(authz.can(null, "view", doc), false);
  assert.strictEqual(authz.can(ada, "view", null), false);
  assert.strictEqual(authz.size(), 0);
});

test("files one answer per person and action", () => {
  const { ada, doc } = seed();
  authz.can(ada, "view", doc);
  authz.can(ada, "view", doc);
  authz.can(ada, "edit", doc);
  assert.strictEqual(authz.size(), 2);
});

test("drops what it worked out for one person and keeps the rest", () => {
  const { ada, gus, doc } = seed();
  authz.can(ada, "view", doc);
  authz.can(gus, "view", doc);
  assert.strictEqual(authz.forget(ada), 1);
  assert.strictEqual(authz.size(), 1);
});

test("answers again from the rules once it has forgotten", () => {
  const { gus, doc } = seed();
  assert.strictEqual(authz.can(gus, "view", doc), false);
  gus.role = "viewer";
  authz.forget(gus);
  assert.strictEqual(authz.can(gus, "view", doc), true);
});
