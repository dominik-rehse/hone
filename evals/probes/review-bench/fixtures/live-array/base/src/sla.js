const MINUTE_MS = 60 * 1000;

// How long a ticket of each priority may wait for its first response.
const TARGET_MINUTES = { urgent: 30, high: 120, normal: 480, low: 1440 };

// How one priority compares with another. A larger number is more urgent.
const RANK = { urgent: 3, high: 2, normal: 1, low: 0 };

function targetMinutes(priority) {
  return TARGET_MINUTES[priority] ?? TARGET_MINUTES.normal;
}

function rank(priority) {
  return RANK[priority] ?? RANK.normal;
}

// When the first response on a ticket falls due.
function dueAt(ticket) {
  return ticket.createdAt + targetMinutes(ticket.priority) * MINUTE_MS;
}

// Minutes to the target. Negative once the target has passed.
function minutesLeft(ticket, now) {
  return Math.round((dueAt(ticket) - now) / MINUTE_MS);
}

// A ticket has breached when it passed its target, closed or not.
function isBreached(ticket, now) {
  const at = ticket.closedAt ?? now;
  return at > dueAt(ticket);
}

module.exports = {
  targetMinutes,
  rank,
  dueAt,
  minutesLeft,
  isBreached,
  TARGET_MINUTES,
  RANK,
  MINUTE_MS,
};
