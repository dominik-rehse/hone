const test = require("node:test");
const assert = require("node:assert");
const lock = require("../src/lock.js");

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test("runs the tasks of one key one after another", async () => {
  lock.reset();
  const order = [];
  const step = (tag, ms) =>
    lock.withLock("A-1", async () => {
      order.push(`${tag} in`);
      await wait(ms);
      order.push(`${tag} out`);
    });
  await Promise.all([step("first", 20), step("second", 0)]);
  assert.deepStrictEqual(order, ["first in", "first out", "second in", "second out"]);
});

test("lets two keys run at the same time", async () => {
  lock.reset();
  const order = [];
  const step = (key, tag, ms) =>
    lock.withLock(key, async () => {
      await wait(ms);
      order.push(tag);
    });
  await Promise.all([step("A-1", "slow", 20), step("B-2", "quick", 0)]);
  assert.deepStrictEqual(order, ["quick", "slow"]);
});

test("gives the task's answer back to its caller", async () => {
  lock.reset();
  assert.strictEqual(await lock.withLock("A-1", () => 7), 7);
});

test("keeps the key working after a task throws", async () => {
  lock.reset();
  await assert.rejects(lock.withLock("A-1", () => Promise.reject(new Error("boom"))));
  assert.strictEqual(await lock.withLock("A-1", () => "still here"), "still here");
});

test("holds a key only while it has work", async () => {
  lock.reset();
  const run = lock.withLock("A-1", () => wait(5));
  assert.strictEqual(lock.isBusy("A-1"), true);
  assert.deepStrictEqual(lock.busyKeys(), ["A-1"]);
  await run;
  await wait(5);
  assert.strictEqual(lock.isBusy("A-1"), false);
});
