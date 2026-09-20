const test = require("node:test");
const assert = require("node:assert");
const queue = require("../src/queue.js");
const jobs = require("../src/jobs.js");
const metrics = require("../src/metrics.js");
const intake = require("../src/intake.js");

test.beforeEach(() => {
  queue.clear();
  metrics.reset();
  jobs.resetIds();
});

test("puts a webhook job on the queue", () => {
  const answer = intake.acceptWebhook({
    tenant: "acme",
    kind: "email",
    body: { to: "ops" },
  });
  assert.strictEqual(answer.accepted, true);
  assert.strictEqual(queue.size(), 1);
  assert.deepStrictEqual(queue.peek().payload, { to: "ops" });
});

test("refuses a body that is not one", () => {
  assert.strictEqual(intake.acceptWebhook(null).reason, "bad-body");
  assert.strictEqual(intake.acceptWebhook("hello").reason, "bad-body");
  assert.strictEqual(queue.size(), 0);
});

test("refuses a job it cannot make", () => {
  assert.strictEqual(
    intake.acceptWebhook({ tenant: "acme", kind: "dance" }).reason,
    "bad-job",
  );
  assert.strictEqual(
    intake.acceptWebhook({ kind: "email" }).reason,
    "bad-job",
  );
});

test("says so when the queue has no room", () => {
  queue.setCapacity(1);
  intake.acceptWebhook({ tenant: "acme", kind: "email" });
  const answer = intake.acceptWebhook({ tenant: "acme", kind: "email" });
  assert.strictEqual(answer.accepted, false);
  assert.strictEqual(answer.reason, "queue-full");
});

test("counts what it took and what it refused", () => {
  intake.acceptWebhook({ tenant: "acme", kind: "email" });
  intake.acceptWebhook(null);
  intake.acceptWebhook({ tenant: "acme", kind: "dance" });
  assert.deepStrictEqual(intake.health(), { accepted: 1, refused: 2 });
});
