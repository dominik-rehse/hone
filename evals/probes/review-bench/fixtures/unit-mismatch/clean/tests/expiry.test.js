const test = require("node:test");
const assert = require("node:assert");
const clock = require("../src/clock.js");
const config = require("../src/config.js");
const sessions = require("../src/sessions.js");
const expiry = require("../src/expiry.js");
const server = require("../src/server.js");

const t0 = 1_700_000_000_000;
const MINUTE = 60 * 1000;
const HOUR = 60 * 60 * 1000;
let at = t0;

function seed(overrides = {}) {
  at = t0;
  clock.setSource(() => at);
  config.load({ sessionTtl: 60, sweepBatch: 2, ...overrides });
  sessions.reset();
  server.resetAttempts();
}

function cookieOf(answer) {
  return answer.headers["Set-Cookie"].split(";")[0];
}

test("a session that has not run out yet is not over", () => {
  seed();
  const session = sessions.create("u-ada");
  assert.strictEqual(expiry.isExpired(session, at), false);
});

test("a session is over at the instant it runs out", () => {
  seed();
  const session = sessions.create("u-ada");
  assert.strictEqual(expiry.isExpired(session, session.expiresAt), true);
  assert.strictEqual(expiry.isExpired(session, session.expiresAt - 1), false);
});

test("a request carries its session past this moment", () => {
  seed();
  const session = sessions.create("u-ada");
  at = t0 + 6 * HOUR;
  expiry.touch(session);
  assert.strictEqual(expiry.isExpired(session, at), false);
  assert.strictEqual(session.seenAt, at);
});

test("a session runs the time the settings give it out from the request", () => {
  seed({ sessionTtl: 30 * 60 });
  const session = sessions.create("u-ada");
  at = t0 + HOUR;
  expiry.touch(session);
  assert.strictEqual(expiry.isExpired(session, at + 29 * MINUTE), false);
  assert.strictEqual(expiry.isExpired(session, at + 31 * MINUTE), true);
});

test("a session carried forward still ends where it would have ended", () => {
  seed();
  const session = sessions.create("u-ada");
  at = t0 + 23 * HOUR;
  expiry.touch(session);
  assert.ok(session.expiresAt <= session.startedAt + sessions.MAX_LIFETIME_MS);
});

test("the sweep takes the sessions that are over", () => {
  seed();
  sessions.create("u-ada");
  sessions.create("u-bo");
  at = t0 + 48 * HOUR;
  assert.strictEqual(expiry.sweep(at), 2);
  assert.strictEqual(sessions.count(), 0);
});

test("the sweep leaves a session a request just carried forward", () => {
  seed();
  const session = sessions.create("u-ada");
  at = t0 + 6 * HOUR;
  expiry.touch(session);
  assert.strictEqual(expiry.sweep(at), 0);
  assert.strictEqual(sessions.count(), 1);
});

test("one pass of the sweep takes at most a batch", () => {
  seed({ sweepBatch: 2 });
  sessions.create("u-ada");
  sessions.create("u-bo");
  sessions.create("u-cy");
  at = t0 + 48 * HOUR;
  assert.strictEqual(expiry.sweep(at), 2);
  assert.strictEqual(sessions.count(), 1);
});

test("the timer's pass sweeps at the time it runs", () => {
  seed();
  sessions.create("u-ada");
  assert.strictEqual(server.runSweep(), 0);
  at = t0 + 48 * HOUR;
  assert.strictEqual(server.runSweep(), 1);
});

test("a request on a session that is over is refused", () => {
  seed();
  const cookie = cookieOf(server.login("u-ada", server.PASSWORD));
  at = t0 + 48 * HOUR;
  const answer = server.whoami(cookie);
  assert.strictEqual(answer.status, 401);
  assert.ok(answer.headers["Set-Cookie"].includes("Max-Age=0"));
  assert.strictEqual(sessions.count(), 0);
});
