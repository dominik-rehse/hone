// Prove that defect (c) bites. Run it with a seeded repository as the working
// directory:
//
//   cd <repo> && node prove-c.js
//
// It exits 0 when the audit entry for a rollout move reads the percentage the
// flag came from, and non-zero when it reads the one it went to.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const admin = load("src/admin.js");
const audit = load("src/audit.js");

admin.create({ key: "checkout-v2", owner: "payments" }, "ops");
admin.setRollout("checkout-v2", 10, "ops");
admin.setRollout("checkout-v2", 40, "ops");

const entry = audit.last();

assert.strictEqual(
  entry.after.rollout.percent,
  40,
  "the entry reads the percentage the flag went to",
);

assert.strictEqual(
  entry.before.rollout.percent,
  10,
  "the entry reads the percentage the flag came from",
);
