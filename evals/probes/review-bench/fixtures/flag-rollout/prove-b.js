// Prove that defect (b) bites. Run it with a seeded repository as the working
// directory:
//
//   cd <repo> && node prove-b.js
//
// It exits 0 when a flag reads the same way after a save and a restore as it
// did before, and non-zero when the restore widens it.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const admin = load("src/admin.js");
const evaluator = load("src/evaluator.js");
const persist = load("src/persist.js");

admin.create({ key: "checkout-v2", owner: "payments" }, "ops");
admin.setEnabled("checkout-v2", true, "ops");
admin.setRollout("checkout-v2", 10, "ops");

assert.strictEqual(
  evaluator.isOn("checkout-v2", { userId: "dennis" }),
  false,
  "dennis sits outside a rollout of ten per cent",
);

const saved = persist.save();
assert.strictEqual(persist.restore(saved), 1, "the backup carries one flag");

assert.strictEqual(
  evaluator.isOn("checkout-v2", { userId: "dennis" }),
  false,
  "dennis still sits outside the rollout once the backup has gone back in",
);
