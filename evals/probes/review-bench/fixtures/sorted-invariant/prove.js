// Prove that the planted defect bites. Run it with a seeded repository as the
// working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove.js
//
// It exits 0 when the lookups in src/find.js read a merged day the same way
// they read a booked one, and non-zero when they do not. So it must pass on
// the `clean` variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const { createCalendar, addSlot } = load("src/calendar.js");
const { findSlot, nextFreeGap } = load("src/find.js");
const { mergeCalendars } = load("src/merge.js");

const at = (hour, minute = 0) => hour * 60 + minute;

// Two teams whose bookings fall through the day one after the other.
const mine = createCalendar("Aurora", at(8), at(18));
addSlot(mine, { start: at(9), end: at(10), title: "Standup", owner: "ana" });
addSlot(mine, { start: at(14), end: at(15), title: "Review", owner: "ben" });

const theirs = createCalendar("Aurora", at(8), at(18));
addSlot(theirs, { start: at(11), end: at(12), title: "Retro", owner: "cleo" });
addSlot(theirs, { start: at(16), end: at(17), title: "Interview", owner: "dev" });

const merged = mergeCalendars(mine, theirs);

assert.strictEqual(merged.slots.length, 4, "the merge keeps all four bookings");

const holder = findSlot(merged, at(11, 30));
assert.strictEqual(
  holder === null ? null : holder.title,
  "Retro",
  "the room display names the booking that holds the merged room at 11:30",
);

assert.deepStrictEqual(
  nextFreeGap(merged, at(11), 90),
  { start: at(12), end: at(13, 30) },
  "the first ninety free minutes after 11:00 begin when the retro ends",
);
