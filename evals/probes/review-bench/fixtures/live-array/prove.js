// Prove that the planted defect bites. Run it with a seeded repository as the
// working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove.js
//
// It exits 0 when a dashboard report leaves the queue as it found it, and
// non-zero when the report reorders the store behind the queue's back. So it
// must pass on the `clean` variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const store = load("src/store.js");
const { nextInQueue } = load("src/queue.js");
const { topByPriority } = load("src/reports/top.js");
const { minuteClock } = load("tests/clock.js");

store.reset(minuteClock());
const oldest = store.add({ subject: "Password reset", requester: "ann", priority: "low" });
store.add({ subject: "Card declined", requester: "bo", priority: "normal" });
store.add({ subject: "Site down", requester: "cy", priority: "urgent" });
store.add({ subject: "Invoice wrong", requester: "di", priority: "high" });

assert.strictEqual(
  nextInQueue().id,
  oldest.id,
  "the queue serves the ticket that has waited longest",
);

topByPriority(3);

assert.strictEqual(
  nextInQueue().id,
  oldest.id,
  "the queue still serves the ticket that has waited longest after a dashboard report",
);
