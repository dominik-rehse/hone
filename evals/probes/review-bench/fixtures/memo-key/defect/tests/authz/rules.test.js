const test = require("node:test");
const assert = require("node:assert");
const rules = require("../../src/authz/rules.js");

const person = (role) => ({ id: "u-1", name: "Someone", role });
const theirs = { id: "d-9", title: "Budget", ownerId: "u-9" };

test("lets a viewer read", () => {
  assert.strictEqual(rules.allows(person("viewer"), "view", theirs), true);
});

test("does not let a viewer write", () => {
  assert.strictEqual(rules.allows(person("viewer"), "edit", theirs), false);
});

test("lets an editor read and write", () => {
  assert.strictEqual(rules.allows(person("editor"), "view", theirs), true);
  assert.strictEqual(rules.allows(person("editor"), "edit", theirs), true);
});

test("does not let an editor share", () => {
  assert.strictEqual(rules.allows(person("editor"), "share", theirs), false);
});

test("lets an administrator do everything the workspace has", () => {
  for (const action of ["view", "edit", "delete", "share"]) {
    assert.strictEqual(rules.allows(person("admin"), action, theirs), true);
  }
});

test("lets a guest do nothing", () => {
  assert.strictEqual(rules.allows(person("guest"), "view", theirs), false);
});

test("refuses a person whose role is not a role", () => {
  assert.strictEqual(rules.allows(person("owner"), "view", theirs), false);
});

test("refuses an action the workspace does not have", () => {
  assert.strictEqual(rules.allows(person("admin"), "publish", theirs), false);
});

test("says who a document belongs to", () => {
  assert.strictEqual(rules.owns(person("viewer"), theirs), false);
  assert.strictEqual(rules.owns({ id: "u-9", role: "guest" }, theirs), true);
});
