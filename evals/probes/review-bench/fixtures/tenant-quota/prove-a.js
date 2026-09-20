// Prove that defect (a) bites. Run it with a seeded repository as the working
// directory, which is where it loads the modules from:
//
//   cd <repo> && node prove-a.js
//
// It exits 0 when a tenant whose jobs the queue had no room for can still put
// a job in once there is room, and non-zero when it has run its window out.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const queue = load("src/queue.js");
const tenants = load("src/tenants.js");
const scheduler = load("src/scheduler.js");

tenants.add({ id: "acme", name: "Acme" });
queue.setCapacity(1);

assert.strictEqual(
  scheduler.submit("acme", "email").accepted,
  true,
  "the first job goes on the queue",
);

for (let i = 0; i < 4; i += 1) {
  assert.strictEqual(
    scheduler.submit("acme", "email").reason,
    "queue-full",
    "a job the queue had no room for comes back queue-full",
  );
}

queue.take();

assert.strictEqual(
  scheduler.submit("acme", "email").accepted,
  true,
  "acme can put a job in once the queue has room again",
);

assert.strictEqual(
  scheduler.remaining("acme"),
  3,
  "acme has spent two of the five its plan buys",
);
