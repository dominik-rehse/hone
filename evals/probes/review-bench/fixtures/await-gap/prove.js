// Prove that the planted defect bites. Run it with a seeded repository as the
// working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove.js
//
// It exits 0 when two people who ask for the same seat at the same time end up
// with one booking between them, and non-zero when they both get it. So it
// must pass on the `clean` variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const store = load("src/store.js");
const lock = load("src/lock.js");
const payments = load("src/payments.js");
const ops = load("src/ops.js");

async function main() {
  store.reset();
  lock.reset();
  payments.reset();

  // The gateway takes a moment to answer, as a card gateway does.
  payments.setDelay(20);

  const results = await Promise.all([
    ops.reserve("A-1", "ann"),
    ops.reserve("A-1", "bo"),
  ]);
  const won = results.filter((result) => result.ok);

  assert.strictEqual(won.length, 1, "one of the two asks for A-1 wins the seat");
  assert.strictEqual(
    store.holderOf("A-1"),
    won[0].booking.user,
    "the seat belongs to the one who won it",
  );
  assert.strictEqual(
    payments.outstandingAuths().length,
    1,
    "the house holds money on one card for A-1, not on two",
  );
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error(err.message);
    process.exit(1);
  },
);
