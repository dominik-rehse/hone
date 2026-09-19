// The provider's events this service has worked through. The provider sends
// the same event more than once, so anything that moves money looks here
// before it does its work, and leaves the event's id behind afterwards.

const handled = new Set();

function alreadyHandled(eventId) {
  return handled.has(eventId);
}

function remember(eventId) {
  handled.add(eventId);
  return eventId;
}

function count() {
  return handled.size;
}

function reset() {
  handled.clear();
}

module.exports = { alreadyHandled, remember, count, reset };
