const store = require("./store.js");
const quotes = require("./quotes.js");
const money = require("./money.js");

// Put a new price on one sku. Gives back what it was and what it is now.
function updatePrice(sku, cents) {
  const before = store.get(sku);
  store.set(sku, cents);
  quotes.invalidate(sku);
  return { sku, before, after: cents };
}

// Take a sku off the price list. Gives back whether it was on it.
function retire(sku) {
  const had = store.remove(sku);
  quotes.invalidate(sku);
  return had;
}

// Move one price by a whole percentage, up or down.
function repriceByPercent(sku, percent) {
  const before = store.get(sku);
  if (before === null) {
    return null;
  }
  return updatePrice(sku, Math.round(before * (1 + percent / 100)));
}

// One line of the price list, for the admin screen.
function priceLine(sku) {
  const cents = store.get(sku);
  return cents === null ? `${sku} -` : `${sku} ${money.formatCents(cents)}`;
}

module.exports = { updatePrice, retire, repriceByPercent, priceLine };
