const key = require("./key.js");
const rules = require("./rules.js");

// The answers worked out so far. A page asks for the same person many times
// over while it draws itself.
const memo = new Map();

// May `user` do `action` to `resource`?
function can(user, action, resource) {
  if (user == null || resource == null) {
    return false;
  }
  const k = key.memoKey(user, action);
  if (memo.has(k)) {
    return memo.get(k);
  }
  const answer = rules.allows(user, action);
  memo.set(k, answer);
  return answer;
}

// Drop what was worked out for one person, after their role moved.
function forget(user) {
  const prefix = key.userPrefix(user);
  let dropped = 0;
  for (const k of [...memo.keys()]) {
    if (k.startsWith(prefix)) {
      memo.delete(k);
      dropped += 1;
    }
  }
  return dropped;
}

function clear() {
  memo.clear();
}

function size() {
  return memo.size;
}

module.exports = { can, forget, clear, size };
