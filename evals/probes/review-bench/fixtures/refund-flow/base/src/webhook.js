const { withRetry } = require("./retry.js");

// Where the payment provider's events come in. One handler per event type.

const handlers = new Map();
const attempts = [];

function on(type, handler) {
  handlers.set(type, handler);
  return handler;
}

function handles(type) {
  return handlers.has(type);
}

// Take one event. The handler runs through withRetry, because the provider
// treats an answer it never got as a delivery that did not happen, and the
// service would rather work an event through now than wait for it to come
// round again.
function receive(event) {
  const handler = handlers.get(event.type);
  if (handler === undefined) {
    return { ok: false, reason: "unhandled" };
  }
  return withRetry(() => handler(event), {
    attempts: 3,
    onAttempt: (n) => attempts.push({ id: event.id, attempt: n }),
  });
}

// How often the receiver has run a handler, one entry per attempt.
function attemptLog() {
  return attempts.slice();
}

function reset() {
  handlers.clear();
  attempts.length = 0;
}

module.exports = { on, handles, receive, attemptLog, reset };
