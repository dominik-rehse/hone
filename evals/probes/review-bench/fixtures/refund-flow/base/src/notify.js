// The mail the shop sends. Every message goes into the outbox first and the
// mailer takes it from there, so a message the mailer cannot take right now
// stays in the outbox and `deliverPending` gets it out later.

const outbox = [];
let downFor = 0;

function deliver(message) {
  if (downFor > 0) {
    downFor -= 1;
    throw new Error("mailer unavailable");
  }
  message.deliveredAt = Date.now();
  return message;
}

// Put one message in the outbox and try to get it out.
function send(to, subject) {
  const message = { to, subject, deliveredAt: null };
  outbox.push(message);
  return deliver(message);
}

// The messages the mailer has not taken yet.
function pending() {
  return outbox.filter((message) => message.deliveredAt === null);
}

// Try the outbox again. The minute job calls this.
function deliverPending() {
  for (const message of pending()) {
    deliver(message);
  }
  return outbox.length - pending().length;
}

// Make the next `n` attempts fail, the way the mailer does while it is down.
function takeDown(n) {
  downFor = n;
}

function all() {
  return outbox.slice();
}

function reset() {
  outbox.length = 0;
  downFor = 0;
}

module.exports = { send, pending, deliverPending, takeDown, all, reset };
