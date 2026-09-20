const test = require("node:test");
const assert = require("node:assert");
const hash = require("../../src/hash.js");
const etag = require("../../src/etag.js");

test("gives the same number for the same text", () => {
  assert.strictEqual(hash.hash32("checkout-v2"), hash.hash32("checkout-v2"));
});

test("holds the numbers it gave when it was written", () => {
  assert.strictEqual(hash.hash32("checkout-v2"), 1571167331);
  assert.strictEqual(hash.hash32("dark-mode"), -1898469990);
  assert.strictEqual(hash.hash32(""), 0);
});

test("joins a pair of strings into one text", () => {
  assert.strictEqual(hash.keyOf("ada", "checkout-v2"), "ada:checkout-v2");
});

test("an etag moves when the body does", () => {
  const one = etag.etagFor({ flags: ["a"] });
  const two = etag.etagFor({ flags: ["a", "b"] });
  assert.notStrictEqual(one, two);
  assert.strictEqual(one, etag.etagFor({ flags: ["a"] }));
});

test("If-None-Match matches one etag out of a list", () => {
  const tag = etag.etagFor("body");
  assert.strictEqual(etag.matches(tag, `W/"other", ${tag}`), true);
  assert.strictEqual(etag.matches(tag, 'W/"other"'), false);
  assert.strictEqual(etag.matches(tag, ""), false);
});
