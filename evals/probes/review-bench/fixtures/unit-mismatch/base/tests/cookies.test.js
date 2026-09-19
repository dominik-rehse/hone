const test = require("node:test");
const assert = require("node:assert");
const config = require("../src/config.js");
const cookies = require("../src/cookies.js");

const session = { id: "s-1", userId: "u-ada" };

test("writes the session cookie the browser keeps", () => {
  config.reset();
  assert.strictEqual(
    cookies.sessionCookie(session),
    "sid=s-1; Path=/; HttpOnly; SameSite=Lax; Max-Age=1800; Secure",
  );
});

test("leaves Secure off where the deployment asks for it", () => {
  config.load({ secureCookie: false, cookieName: "session" });
  assert.strictEqual(
    cookies.sessionCookie(session),
    "session=s-1; Path=/; HttpOnly; SameSite=Lax; Max-Age=1800",
  );
  config.reset();
});

test("carries the deployment's own Max-Age", () => {
  config.load({ sessionTtl: 600 });
  assert.ok(cookies.sessionCookie(session).includes("Max-Age=600"));
  config.reset();
});

test("writes a header that takes the cookie away", () => {
  config.reset();
  assert.strictEqual(cookies.clearCookie(), "sid=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0");
});

test("reads one cookie out of a header", () => {
  assert.strictEqual(cookies.readCookie("theme=dark; sid=s-7; lang=en", "sid"), "s-7");
  assert.strictEqual(cookies.readCookie(" sid = s-8 ", "sid"), "s-8");
});

test("has nothing for a header without the cookie in it", () => {
  assert.strictEqual(cookies.readCookie("theme=dark", "sid"), null);
  assert.strictEqual(cookies.readCookie(undefined, "sid"), null);
  assert.strictEqual(cookies.readCookie("broken", "sid"), null);
});
