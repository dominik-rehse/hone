const test = require("node:test");
const assert = require("node:assert");
const docs = require("../src/docs.js");

function seed() {
  docs.reset();
  return docs.create({ title: "Q3 plan", ownerId: "u-ada" });
}

test("gives a new document an id and an owner", () => {
  const doc = seed();
  assert.strictEqual(doc.id, "d-1");
  assert.strictEqual(doc.ownerId, "u-ada");
  assert.strictEqual(doc.lockedBy, null);
});

test("finds a document by its id, and nothing for an unknown one", () => {
  const doc = seed();
  assert.strictEqual(docs.get(doc.id).title, "Q3 plan");
  assert.strictEqual(docs.get("d-99"), null);
});

test("writes a body and stamps the time", () => {
  const doc = seed();
  assert.strictEqual(docs.save(doc.id, "hello", 17).body, "hello");
  assert.strictEqual(docs.get(doc.id).updatedAt, 17);
  assert.strictEqual(docs.save("d-99", "hello"), null);
});

test("takes a document off the shelf once", () => {
  const doc = seed();
  assert.strictEqual(docs.remove(doc.id), true);
  assert.strictEqual(docs.remove(doc.id), false);
  assert.strictEqual(docs.get(doc.id), null);
});

test("will not take a locked document off the shelf", () => {
  const doc = seed();
  docs.lock(doc.id, "u-gus");
  assert.throws(() => docs.remove(doc.id), (err) => err.code === "DOC_LOCKED");
  docs.unlock(doc.id);
  assert.strictEqual(docs.remove(doc.id), true);
});

test("lists what one person owns", () => {
  const doc = seed();
  docs.create({ title: "Budget", ownerId: "u-gus" });
  assert.deepStrictEqual(docs.ownedBy("u-ada").map((d) => d.id), [doc.id]);
});
