const { formatTime, spanMinutes } = require("./time.js");

// One booking on one line: the span it holds, then what it is for.
function formatSlot(slot) {
  return `${formatTime(slot.start)}-${formatTime(slot.end)}  ${slot.title}`;
}

// A span of minutes as a short length: "90m" reads "1h 30m".
function formatLength(minutes) {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours === 0) {
    return `${rest}m`;
  }
  return rest === 0 ? `${hours}h` : `${hours}h ${rest}m`;
}

// The day's bookings under a heading, one per line.
function formatDay(calendar) {
  const head = `${calendar.room}  ${formatTime(calendar.opensAt)}-${formatTime(calendar.closesAt)}`;
  const rows = calendar.slots.map((slot) => `  ${formatSlot(slot)}`);
  return [head, ...rows].join("\n");
}

// The line the room display shows for a free span.
function formatGap(gap) {
  if (gap === null) {
    return "no free span left today";
  }
  return `free ${formatTime(gap.start)}-${formatTime(gap.end)} (${formatLength(spanMinutes(gap))})`;
}

module.exports = { formatSlot, formatLength, formatDay, formatGap };
