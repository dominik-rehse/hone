const clock = require("./clock.js");
const config = require("./config.js");
const sessions = require("./sessions.js");

// Whether a session is over at `now`. A session is over at the instant it
// runs out, not after it.
function isExpired(session, now) {
  return session.expiresAt <= now;
}

// Carry a session forward from the request that just came in. A session that
// has been carried forward all day still ends where it would have ended.
function touch(session) {
  const until = clock.after(config.current().sessionTtl * 1000);
  const latest = session.startedAt + sessions.MAX_LIFETIME_MS;
  session.seenAt = clock.now();
  session.expiresAt = Math.min(until, latest);
  return session;
}

// Take the sessions that are over off the shelf. One pass takes at most a
// batch of them, so a long backlog is worked off over several passes rather
// than in one. Gives back how many it took.
function sweep(now = clock.now()) {
  const over = sessions.all().filter((session) => isExpired(session, now));
  const batch = over.slice(0, config.current().sweepBatch);
  for (const session of batch) {
    sessions.destroy(session.id);
  }
  return batch.length;
}

module.exports = { isExpired, touch, sweep };
