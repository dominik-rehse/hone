// The quantity breaks the sales team agreed, steepest first.
const BREAKS = [
  { min: 100, off: 0.1 },
  { min: 25, off: 0.05 },
  { min: 10, off: 0.02 },
];

// The break a quantity earns, or null for a quantity under the smallest one.
function breakFor(qty) {
  return BREAKS.find((b) => qty >= b.min) ?? null;
}

// What `qty` of an item at `unitCents` comes to, with its break taken off.
function lineTotal(unitCents, qty) {
  const gross = unitCents * qty;
  const found = breakFor(qty);
  return found === null ? gross : Math.round(gross * (1 - found.off));
}

module.exports = { BREAKS, breakFor, lineTotal };
