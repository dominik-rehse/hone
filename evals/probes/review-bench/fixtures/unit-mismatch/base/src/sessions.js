const clock = require("./clock.js");
const tokens = require("./tokens.js");

// However long somebody keeps working, one session is over a day after it
// began and they sign in again.
const MAX_LIFETIME_MS = 24 * 60 * 60 * 1000;

const open = new Map();

function create(userId) {
  const startedAt = clock.now();
  const session = {
    id: tokens.next(),
    userId,
    startedAt,
    seenAt: startedAt,
    expiresAt: clock.after(MAX_LIFETIME_MS),
  };
  open.set(session.id, session);
  return session;
}

function get(id) {
  return open.get(id) ?? null;
}

function destroy(id) {
  return open.delete(id);
}

function all() {
  return [...open.values()];
}

function ofUser(userId) {
  return all().filter((session) => session.userId === userId);
}

function count() {
  return open.size;
}

function reset() {
  open.clear();
  tokens.reset();
}

module.exports = { create, get, destroy, all, ofUser, count, reset, MAX_LIFETIME_MS };
