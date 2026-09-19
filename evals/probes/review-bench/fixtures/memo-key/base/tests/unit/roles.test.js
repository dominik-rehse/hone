const test = require("node:test");
const assert = require("node:assert");
const roles = require("../../src/authz/roles.js");

test("knows the roles it has and no others", () => {
  assert.strictEqual(roles.isRole("viewer"), true);
  assert.strictEqual(roles.isRole("owner"), false);
});

test("orders the roles weakest first", () => {
  assert.ok(roles.rank("admin") > roles.rank("editor"));
  assert.ok(roles.rank("editor") > roles.rank("viewer"));
  assert.ok(roles.rank("viewer") > roles.rank("guest"));
});

test("gives a role the actions it holds", () => {
  assert.deepStrictEqual(roles.actionsOf("viewer"), ["view"]);
  assert.deepStrictEqual(roles.actionsOf("guest"), []);
  assert.ok(roles.actionsOf("admin").includes("share"));
});

test("has no actions for a name that is not a role", () => {
  assert.deepStrictEqual(roles.actionsOf("owner"), []);
  assert.strictEqual(roles.rank("owner"), -1);
});

test("compares one role with another", () => {
  assert.strictEqual(roles.atLeast("admin", "viewer"), true);
  assert.strictEqual(roles.atLeast("viewer", "viewer"), true);
  assert.strictEqual(roles.atLeast("viewer", "editor"), false);
  assert.strictEqual(roles.atLeast("owner", "viewer"), false);
});
