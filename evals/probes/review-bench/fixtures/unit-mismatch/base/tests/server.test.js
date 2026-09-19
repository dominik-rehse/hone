const test = require("node:test");
const assert = require("node:assert");
const clock = require("../src/clock.js");
const config = require("../src/config.js");
const sessions = require("../src/sessions.js");
const server = require("../src/server.js");

const t0 = 1_700_000_000_000;
let at = t0;

function seed() {
  at = t0;
  clock.setSource(() => at);
  config.reset();
  sessions.reset();
  server.resetAttempts();
}

// The Cookie header a browser would send back after a Set-Cookie.
function cookieOf(answer) {
  return answer.headers["Set-Cookie"].split(";")[0];
}

test("signs somebody in and hands out a cookie", () => {
  seed();
  const answer = server.login("u-ada", server.PASSWORD);
  assert.strictEqual(answer.status, 200);
  assert.ok(answer.headers["Set-Cookie"].startsWith("sid=s-1"));
  assert.deepStrictEqual(answer.body, { userId: "u-ada" });
});

test("refuses the wrong password", () => {
  seed();
  assert.strictEqual(server.login("u-ada", "guess").status, 401);
  assert.strictEqual(sessions.count(), 0);
});

test("tells the browser who is asking", () => {
  seed();
  const answer = server.whoami(cookieOf(server.login("u-ada", server.PASSWORD)));
  assert.strictEqual(answer.status, 200);
  assert.deepStrictEqual(answer.body, { userId: "u-ada" });
});

test("refuses a request that carries no session we know", () => {
  seed();
  assert.strictEqual(server.whoami("sid=s-99").status, 401);
  assert.strictEqual(server.whoami("").status, 401);
});

test("signs somebody out and takes the cookie away", () => {
  seed();
  const cookie = cookieOf(server.login("u-ada", server.PASSWORD));
  const answer = server.logout(cookie);
  assert.strictEqual(answer.status, 200);
  assert.ok(answer.headers["Set-Cookie"].includes("Max-Age=0"));
  assert.strictEqual(server.whoami(cookie).status, 401);
});

test("locks an account out after too many wrong passwords", () => {
  seed();
  for (let i = 0; i < config.current().loginAttempts; i += 1) {
    assert.strictEqual(server.login("u-ada", "guess").status, 401);
  }
  assert.strictEqual(server.login("u-ada", server.PASSWORD).status, 429);
});

test("lets them in again once the lockout is over", () => {
  seed();
  for (let i = 0; i < config.current().loginAttempts; i += 1) {
    server.login("u-ada", "guess");
  }
  at = t0 + server.LOCKOUT_MS + 1;
  assert.strictEqual(server.login("u-ada", server.PASSWORD).status, 200);
});
