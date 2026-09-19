// The card gateway the till talks to, with the stand-in the house runs against
// in a test hall. The settlement run at the end of the night captures the holds
// with a booking behind them and lets every other one go, a hold from a seat
// somebody gave back included. So only a booking that fails on the spot has a
// hold to give back early.

let delayMs = 0;
let nextId = 1;
const declined = new Set();
const underfunded = new Set();
const outstanding = new Map();

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// How long the gateway takes to answer, in milliseconds.
function setDelay(ms) {
  delayMs = ms;
}

// The gateway turns this user's card down.
function declineCard(user) {
  declined.add(user);
}

// The gateway holds less on this user's card than the till asks for.
function underfundCard(user) {
  underfunded.add(user);
}

// Put `cents` aside on the user's card for the booking about to be written.
async function preauthorize(user, cents) {
  await wait(delayMs);
  if (declined.has(user)) {
    return { ok: false, decline: "card-declined" };
  }
  const held = underfunded.has(user) ? Math.floor(cents / 2) : cents;
  const id = `auth-${nextId}`;
  nextId += 1;
  outstanding.set(id, { id, user, cents: held });
  return { ok: true, id, cents: held };
}

// Let a pre-authorization go now rather than at the settlement run.
async function release(id) {
  await wait(delayMs);
  if (!outstanding.has(id)) {
    const err = new Error(`no pre-authorization to release: ${id}`);
    err.code = "ALREADY_RELEASED";
    throw err;
  }
  outstanding.delete(id);
  return true;
}

// What the gateway is holding right now.
function outstandingAuths() {
  return [...outstanding.values()];
}

function reset() {
  delayMs = 0;
  nextId = 1;
  declined.clear();
  underfunded.clear();
  outstanding.clear();
}

module.exports = {
  setDelay,
  declineCard,
  underfundCard,
  preauthorize,
  release,
  outstandingAuths,
  reset,
};
