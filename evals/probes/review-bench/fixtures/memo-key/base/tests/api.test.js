const test = require("node:test");
const assert = require("node:assert");
const api = require("../src/api.js");
const docs = require("../src/docs.js");
const users = require("../src/users.js");
const authz = require("../src/authz/can.js");

function seed() {
  docs.reset();
  users.reset();
  authz.clear();
  const ada = users.add({ id: "u-ada", name: "Ada", role: "editor" });
  const gus = users.add({ id: "u-gus", name: "Gus", role: "guest" });
  const mel = users.add({ id: "u-mel", name: "Mel", role: "admin" });
  const doc = docs.create({ title: "Q3 plan", ownerId: ada.id });
  return { ada, gus, mel, doc };
}

test("opens a document for somebody who may read it", () => {
  const { ada, doc } = seed();
  const answer = api.openDoc(ada.id, doc.id);
  assert.strictEqual(answer.status, 200);
  assert.strictEqual(answer.body.title, "Q3 plan");
});

test("refuses to open a document for a guest", () => {
  const { gus, doc } = seed();
  assert.strictEqual(api.openDoc(gus.id, doc.id).status, 403);
});

test("has nothing for an unknown person or document", () => {
  const { ada, doc } = seed();
  assert.strictEqual(api.openDoc("u-nobody", doc.id).status, 404);
  assert.strictEqual(api.openDoc(ada.id, "d-99").status, 404);
});

test("saves a body for somebody who may write", () => {
  const { ada, doc } = seed();
  assert.strictEqual(api.saveDoc(ada.id, doc.id, "hello", 5).status, 200);
  assert.strictEqual(docs.get(doc.id).body, "hello");
});

test("refuses a save from somebody who may only read", () => {
  const { gus, doc } = seed();
  assert.strictEqual(api.saveDoc(gus.id, doc.id, "hello").status, 403);
  assert.strictEqual(docs.get(doc.id).body, "");
});

test("shares a document only for a role that may share", () => {
  const { ada, mel, doc } = seed();
  assert.strictEqual(api.shareDoc(ada.id, doc.id, mel.id).status, 403);
  assert.strictEqual(api.shareDoc(mel.id, doc.id, ada.id).status, 200);
});

test("lets an administrator move somebody to another role", () => {
  const { gus, mel, doc } = seed();
  assert.strictEqual(api.openDoc(gus.id, doc.id).status, 403);
  assert.strictEqual(api.changeRole(mel.id, gus.id, "viewer").status, 200);
  assert.strictEqual(api.openDoc(gus.id, doc.id).status, 200);
});

test("refuses a role change from anybody else", () => {
  const { ada, gus } = seed();
  assert.strictEqual(api.changeRole(ada.id, gus.id, "admin").status, 403);
  assert.strictEqual(users.get(gus.id).role, "guest");
});

test("has nothing to change for an unknown person or a role that is not one", () => {
  const { mel, gus } = seed();
  assert.strictEqual(api.changeRole(mel.id, "u-nobody", "viewer").status, 404);
  assert.strictEqual(api.changeRole(mel.id, gus.id, "owner").status, 404);
});
