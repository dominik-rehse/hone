// Prove that the planted defect bites. Run it with a seeded repository as the
// working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove.js
//
// It exits 0 when a viewer who has written their own document is still refused
// somebody else's, and non-zero when the second write goes through. So it must
// pass on the `clean` variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const api = load("src/api.js");
const docs = load("src/docs.js");
const users = load("src/users.js");

docs.reset();
users.reset();

const ada = users.add({ id: "u-ada", name: "Ada", role: "viewer" });
users.add({ id: "u-mel", name: "Mel", role: "admin" });
const adaDoc = docs.create({ title: "Q3 plan", ownerId: "u-ada" });
const melDoc = docs.create({ title: "Budget", ownerId: "u-mel" });

assert.strictEqual(
  api.saveDoc(ada.id, adaDoc.id, "my own notes").status,
  200,
  "Ada writes the document that belongs to her",
);

assert.strictEqual(
  api.saveDoc(ada.id, melDoc.id, "not mine").status,
  403,
  "Ada is a viewer, so Mel's document is not hers to write",
);
assert.strictEqual(docs.get(melDoc.id).body, "", "Mel's document is untouched");
