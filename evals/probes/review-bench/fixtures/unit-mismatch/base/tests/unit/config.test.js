const test = require("node:test");
const assert = require("node:assert");
const config = require("../../src/config.js");

test("starts from the defaults", () => {
  const settings = config.reset();
  assert.strictEqual(settings.cookieName, "sid");
  assert.strictEqual(settings.sessionTtl, config.DEFAULTS.sessionTtl);
});

test("writes the deployment's values over them", () => {
  const settings = config.load({ cookieName: "session", sessionTtl: 600 });
  assert.strictEqual(settings.cookieName, "session");
  assert.strictEqual(settings.sessionTtl, 600);
  assert.strictEqual(settings.sweepBatch, config.DEFAULTS.sweepBatch);
});

test("drops a setting it does not know", () => {
  const settings = config.load({ nonsense: 1 });
  assert.strictEqual(settings.nonsense, undefined);
});

test("keeps the default where a number is not one", () => {
  const settings = config.load({ sessionTtl: "600", sweepBatch: 0, loginAttempts: -2 });
  assert.strictEqual(settings.sessionTtl, config.DEFAULTS.sessionTtl);
  assert.strictEqual(settings.sweepBatch, config.DEFAULTS.sweepBatch);
  assert.strictEqual(settings.loginAttempts, config.DEFAULTS.loginAttempts);
});

test("gives the same settings back until they are loaded again", () => {
  config.load({ cookieName: "session" });
  assert.strictEqual(config.current().cookieName, "session");
  config.reset();
  assert.strictEqual(config.current().cookieName, "sid");
});
