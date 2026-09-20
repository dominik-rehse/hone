// Prove that defect (c) bites. Run it with a seeded repository as the working
// directory:
//
//   cd <repo> && node prove-c.js
//
// It exits 0 when the paid tenant's job comes off the queue ahead of the jobs
// the old webhook put there, and non-zero when it waits behind them.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const queue = load("src/queue.js");
const tenants = load("src/tenants.js");
const intake = load("src/intake.js");
const scheduler = load("src/scheduler.js");
const dispatch = load("src/dispatch.js");

tenants.add({ id: "mint", name: "Mint", plan: "paid" });

assert.strictEqual(
  intake.acceptWebhook({ tenant: "beta", kind: "email" }).accepted,
  true,
  "the old webhook put a job on the queue",
);
assert.strictEqual(
  intake.acceptWebhook({ tenant: "beta", kind: "report" }).accepted,
  true,
  "the old webhook put a second job on the queue",
);

const paid = scheduler.submit("mint", "report");
assert.strictEqual(paid.accepted, true, "the paid tenant's job went on too");

const batch = dispatch.nextBatch(1);

assert.strictEqual(
  batch[0].id,
  paid.id,
  "the paid tenant's job comes off the queue first",
);

assert.strictEqual(queue.size(), 2, "the two webhook jobs are still waiting");
