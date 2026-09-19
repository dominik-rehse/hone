const test = require("node:test");
const assert = require("node:assert");
const leases = require("../src/leases.js");

const t0 = 1_700_000_000_000;

test("hands the lease to the first to ask", () => {
  leases.reset();
  const lease = leases.acquire("nightly", "worker-1", t0);
  assert.strictEqual(lease.owner, "worker-1");
  assert.strictEqual(lease.expiresAt, t0 + leases.LEASE_MS);
});

test("turns the next worker away while it is somebody's", () => {
  leases.reset();
  leases.acquire("nightly", "worker-1", t0);
  assert.strictEqual(leases.acquire("nightly", "worker-2", t0 + 1000), null);
  assert.strictEqual(leases.holder("nightly", t0 + 1000), "worker-1");
});

test("hands it on once it has been given back", () => {
  leases.reset();
  leases.acquire("nightly", "worker-1", t0);
  assert.strictEqual(leases.release("nightly", "worker-1"), true);
  assert.strictEqual(leases.isHeld("nightly", t0), false);
  assert.notStrictEqual(leases.acquire("nightly", "worker-2", t0 + 1000), null);
});

test("hands it on once it has run its time out", () => {
  leases.reset();
  leases.acquire("nightly", "worker-1", t0);
  const later = t0 + leases.LEASE_MS + 1;
  assert.strictEqual(leases.isHeld("nightly", later), false);
  assert.notStrictEqual(leases.acquire("nightly", "worker-2", later), null);
});

test("will not let another worker give it back", () => {
  leases.reset();
  leases.acquire("nightly", "worker-1", t0);
  assert.strictEqual(leases.release("nightly", "worker-2"), false);
  assert.strictEqual(leases.release("weekly", "worker-1"), false);
  assert.strictEqual(leases.isHeld("nightly", t0), true);
});

test("keeps one key clear of another", () => {
  leases.reset();
  leases.acquire("nightly", "worker-1", t0);
  assert.notStrictEqual(leases.acquire("weekly", "worker-2", t0), null);
});
