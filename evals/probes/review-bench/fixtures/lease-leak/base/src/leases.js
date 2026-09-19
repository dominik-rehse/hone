// One worker at a time on one key. A lease that nobody gave back is free again
// once it has run its time out, so a worker that died does not stop the world
// for good.
const LEASE_MS = 5 * 60 * 1000;

const held = new Map();

// Take the lease on `key`. Null while it is somebody's.
function acquire(key, owner, now, ms = LEASE_MS) {
  const lease = held.get(key);
  if (lease !== undefined && lease.expiresAt > now) {
    return null;
  }
  const taken = { key, owner, takenAt: now, expiresAt: now + ms };
  held.set(key, taken);
  return taken;
}

// Give the lease back. False when it is not yours to give back.
function release(key, owner) {
  const lease = held.get(key);
  if (lease === undefined || lease.owner !== owner) {
    return false;
  }
  held.delete(key);
  return true;
}

function isHeld(key, now) {
  const lease = held.get(key);
  return lease !== undefined && lease.expiresAt > now;
}

function holder(key, now) {
  return isHeld(key, now) ? held.get(key).owner : null;
}

function reset() {
  held.clear();
}

module.exports = { acquire, release, isHeld, holder, reset, LEASE_MS };
