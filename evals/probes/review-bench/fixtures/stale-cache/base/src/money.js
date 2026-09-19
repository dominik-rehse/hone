// Every amount in this service is whole cents. These two functions are the
// only place a decimal string and a cent count meet.

// "12.50" -> 1250. Null for anything that is not a plain amount.
function parseAmount(text) {
  const trimmed = String(text).trim();
  if (!/^\d+(\.\d{1,2})?$/.test(trimmed)) {
    return null;
  }
  const [whole, frac = ""] = trimmed.split(".");
  return Number(whole) * 100 + Number(frac.padEnd(2, "0"));
}

// 1250 -> "12.50".
function formatCents(cents) {
  const sign = cents < 0 ? "-" : "";
  const n = Math.abs(cents);
  return `${sign}${Math.floor(n / 100)}.${String(n % 100).padStart(2, "0")}`;
}

module.exports = { parseAmount, formatCents };
