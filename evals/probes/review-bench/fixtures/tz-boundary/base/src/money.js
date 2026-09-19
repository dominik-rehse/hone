// Money is whole cents everywhere below the renderer.

// What one invoice line comes to.
function lineTotalCents(line) {
  return Math.round(line.unitCents * line.quantity);
}

function sumCents(values) {
  return values.reduce((total, cents) => total + cents, 0);
}

// The tax on an amount, at a rate given as a fraction.
function vatCents(cents, rate) {
  return Math.round(cents * rate);
}

// Cents as the invoice prints them.
function formatCents(cents) {
  const sign = cents < 0 ? "-" : "";
  const whole = Math.abs(cents);
  return `${sign}${Math.floor(whole / 100)}.${String(whole % 100).padStart(2, "0")} EUR`;
}

module.exports = { lineTotalCents, sumCents, vatCents, formatCents };
