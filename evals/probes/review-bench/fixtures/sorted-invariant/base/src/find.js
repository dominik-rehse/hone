// The index of the first booking that has not ended by `minute`.
function firstFrom(slots, minute) {
  let lo = 0;
  let hi = slots.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (slots[mid].end <= minute) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

// The booking that holds the room at `minute`, or null when it is free then.
function findSlot(calendar, minute) {
  const slot = calendar.slots[firstFrom(calendar.slots, minute)];
  return slot !== undefined && slot.start <= minute ? slot : null;
}

// The first span of `minutes` the room is free for, at or after `from`. Null
// when the room closes before such a span fits.
function nextFreeGap(calendar, from, minutes) {
  let at = Math.max(from, calendar.opensAt);
  for (let i = firstFrom(calendar.slots, at); i < calendar.slots.length; i += 1) {
    const slot = calendar.slots[i];
    if (slot.start - at >= minutes) {
      break;
    }
    at = Math.max(at, slot.end);
  }
  if (at + minutes > calendar.closesAt) {
    return null;
  }
  return { start: at, end: at + minutes };
}

// Is the room free for the whole of `start`..`end`?
function isFree(calendar, start, end) {
  if (start < calendar.opensAt || end > calendar.closesAt) {
    return false;
  }
  const slot = calendar.slots[firstFrom(calendar.slots, start)];
  return slot === undefined || slot.start >= end;
}

module.exports = { firstFrom, findSlot, nextFreeGap, isFree };
