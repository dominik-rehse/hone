// A time of day is a whole number of minutes since midnight.

const DAY_MINUTES = 24 * 60;

// "09:30" as 570.
function parseTime(text) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(text).trim());
  if (m === null) {
    throw new Error(`not a time of day: ${text}`);
  }
  const hours = Number(m[1]);
  const minutes = Number(m[2]);
  if (hours > 23 || minutes > 59) {
    throw new Error(`not a time of day: ${text}`);
  }
  return hours * 60 + minutes;
}

// 570 as "09:30".
function formatTime(minutes) {
  const total = ((Math.round(minutes) % DAY_MINUTES) + DAY_MINUTES) % DAY_MINUTES;
  const hours = Math.floor(total / 60);
  return `${String(hours).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

// How long the span runs, in minutes.
function spanMinutes(span) {
  return span.end - span.start;
}

// Do the two spans hold any minute in common?
function overlaps(a, b) {
  return a.start < b.end && b.start < a.end;
}

// Is the whole of `inner` inside `outer`?
function contains(outer, inner) {
  return inner.start >= outer.start && inner.end <= outer.end;
}

module.exports = {
  DAY_MINUTES,
  parseTime,
  formatTime,
  spanMinutes,
  overlaps,
  contains,
};
