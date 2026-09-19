const test = require("node:test");
const assert = require("node:assert");
const authz = require("../../src/authz/can.js");
const api = require("../../src/api.js");
const docs = require("../../src/docs.js");
const users = require("../../src/users.js");

function seed() {
  docs.reset();
  users.reset();
  authz.clear();
  const ada = users.add({ id: "u-ada", name: "Ada", role: "viewer" });
  const gus = users.add({ id: "u-gus", name: "Gus", role: "guest" });
  const mel = users.add({ id: "u-mel", name: "Mel", role: "admin" });
  const adaDoc = docs.create({ title: "Q3 plan", ownerId: ada.id });
  const melDoc = docs.create({ title: "Budget", ownerId: mel.id });
  const gusDoc = docs.create({ title: "Handover", ownerId: gus.id });
  return { ada, gus, mel, adaDoc, melDoc, gusDoc };
}

test("the person a document belongs to may open it", () => {
  const { gus, gusDoc } = seed();
  assert.strictEqual(authz.can(gus, "view", gusDoc), true);
});

test("the person a document belongs to may write it", () => {
  const { ada, adaDoc } = seed();
  assert.strictEqual(authz.can(ada, "edit", adaDoc), true);
});

test("the person a document belongs to may take it away", () => {
  const { ada, adaDoc } = seed();
  assert.strictEqual(authz.can(ada, "delete", adaDoc), true);
});

test("a guest gets nothing from a document that is not theirs", () => {
  const { gus, melDoc } = seed();
  assert.strictEqual(authz.can(gus, "edit", melDoc), false);
});

test("owning a document does not hand over the other actions", () => {
  const { ada, adaDoc } = seed();
  assert.strictEqual(authz.can(ada, "share", adaDoc), false);
});

test("an administrator may still take away what is not theirs", () => {
  const { mel, adaDoc } = seed();
  assert.strictEqual(authz.can(mel, "delete", adaDoc), true);
});

test("the owner deletes their document through the api", () => {
  const { ada, adaDoc } = seed();
  assert.deepStrictEqual(api.deleteDoc(ada.id, adaDoc.id), {
    status: 200,
    body: { id: adaDoc.id, deleted: true },
  });
  assert.strictEqual(docs.get(adaDoc.id), null);
});

test("a guest is refused the delete", () => {
  const { gus, melDoc } = seed();
  assert.strictEqual(api.deleteDoc(gus.id, melDoc.id).status, 403);
  assert.notStrictEqual(docs.get(melDoc.id), null);
});

test("a document open in another window is not deleted", () => {
  const { ada, adaDoc } = seed();
  docs.lock(adaDoc.id, "u-gus");
  assert.strictEqual(api.deleteDoc(ada.id, adaDoc.id).status, 409);
  assert.notStrictEqual(docs.get(adaDoc.id), null);
});

test("the toolbar of the document I own carries write and delete", () => {
  const { ada, adaDoc } = seed();
  assert.deepStrictEqual(api.docMenu(ada.id, adaDoc.id).body, ["view", "edit", "delete"]);
});

test("the toolbar has nothing on a document a guest looks at", () => {
  const { gus, melDoc } = seed();
  assert.deepStrictEqual(api.docMenu(gus.id, melDoc.id).body, []);
});
