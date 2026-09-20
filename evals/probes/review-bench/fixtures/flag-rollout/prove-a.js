// Prove that defect (a) bites. Run it with a seeded repository as the working
// directory, which is where it loads the modules from:
//
//   cd <repo> && node prove-a.js
//
// It exits 0 when a rollout of one per cent leaves out the callers it should
// leave out, and non-zero when it takes in a crowd of them.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const admin = load("src/admin.js");
const evaluator = load("src/evaluator.js");

admin.create({ key: "checkout-v2", owner: "payments" }, "ops");
admin.setEnabled("checkout-v2", true, "ops");
admin.setRollout("checkout-v2", 1, "ops");

assert.strictEqual(
  evaluator.isOn("checkout-v2", { userId: "ada" }),
  false,
  "a rollout of one per cent leaves ada out",
);

const callers = Array.from({ length: 400 }, (_, i) => `caller-${i}`);
const inside = callers.filter((userId) =>
  evaluator.isOn("checkout-v2", { userId }),
).length;

assert.ok(
  inside <= 40,
  `a rollout of one per cent took ${inside} of ${callers.length} callers`,
);
