// A day in the invoicing module is written YYYY-MM-DD.

const DAY_MS = 24 * 60 * 60 * 1000;

// The day a written date names.
function fromIsoDate(text) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(text).trim());
  if (m === null) {
    throw new Error(`not a date: ${text}`);
  }
  return new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
}

// The day `d` falls on, written out.
function toIsoDate(d) {
  return d.toISOString().slice(0, 10);
}

function startOfDayUtc(d) {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

// `n` days on from `d`.
function addDaysUtc(d, n) {
  return new Date(startOfDayUtc(d).getTime() + n * DAY_MS);
}

// How many whole days lie from `from` to `to`.
function daysBetweenUtc(from, to) {
  return Math.round(
    (startOfDayUtc(to).getTime() - startOfDayUtc(from).getTime()) / DAY_MS,
  );
}

// Does `a` fall after `b`?
function isAfterUtc(a, b) {
  return startOfDayUtc(a).getTime() > startOfDayUtc(b).getTime();
}

module.exports = {
  DAY_MS,
  fromIsoDate,
  toIsoDate,
  startOfDayUtc,
  addDaysUtc,
  daysBetweenUtc,
  isAfterUtc,
};
