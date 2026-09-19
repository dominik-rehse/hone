const test = require("node:test");
const assert = require("node:assert");
const clock = require("../src/clock.js");
const sessions = require("../src/sessions.js");

const t0 = 1_700_000_000_000;
let at = t0;

function seed() {
  at = t0;
  clock.setSource(() => at);
  sessions.reset();
}

test("opens a session with an id of its own", () => {
  seed();
  const one = sessions.create("u-ada");
  const two = sessions.create("u-bo");
  assert.strictEqual(one.id, "s-1");
  assert.notStrictEqual(one.id, two.id);
  assert.strictEqual(one.userId, "u-ada");
});

test("stamps a session with the time it began", () => {
  seed();
  const session = sessions.create("u-ada");
  assert.strictEqual(session.startedAt, t0);
  assert.strictEqual(session.seenAt, t0);
});

test("ends a session a day after it began", () => {
  seed();
  const session = sessions.create("u-ada");
  assert.strictEqual(session.expiresAt, t0 + sessions.MAX_LIFETIME_MS);
});

test("finds a session by its id, and nothing for an unknown one", () => {
  seed();
  const session = sessions.create("u-ada");
  assert.strictEqual(sessions.get(session.id).userId, "u-ada");
  assert.strictEqual(sessions.get("s-99"), null);
});

test("takes a session off the shelf once", () => {
  seed();
  const session = sessions.create("u-ada");
  assert.strictEqual(sessions.destroy(session.id), true);
  assert.strictEqual(sessions.destroy(session.id), false);
  assert.strictEqual(sessions.count(), 0);
});

test("lists what one person has open", () => {
  seed();
  sessions.create("u-ada");
  sessions.create("u-bo");
  sessions.create("u-ada");
  assert.strictEqual(sessions.ofUser("u-ada").length, 2);
  assert.strictEqual(sessions.count(), 3);
});
