const test = require("node:test");
const assert = require("node:assert");
const rules = require("../../src/authz/rules.js");

const person = (role) => ({ id: "u-1", name: "Someone", role });

test("lets a viewer read", () => {
  assert.strictEqual(rules.allows(person("viewer"), "view"), true);
});

test("does not let a viewer write", () => {
  assert.strictEqual(rules.allows(person("viewer"), "edit"), false);
});

test("lets an editor read and write", () => {
  assert.strictEqual(rules.allows(person("editor"), "view"), true);
  assert.strictEqual(rules.allows(person("editor"), "edit"), true);
});

test("does not let an editor share", () => {
  assert.strictEqual(rules.allows(person("editor"), "share"), false);
});

test("lets an administrator do everything the workspace has", () => {
  for (const action of ["view", "edit", "delete", "share"]) {
    assert.strictEqual(rules.allows(person("admin"), action), true);
  }
});

test("lets a guest do nothing", () => {
  assert.strictEqual(rules.allows(person("guest"), "view"), false);
});

test("refuses a person whose role is not a role", () => {
  assert.strictEqual(rules.allows(person("owner"), "view"), false);
});

test("refuses an action the workspace does not have", () => {
  assert.strictEqual(rules.allows(person("admin"), "publish"), false);
});
