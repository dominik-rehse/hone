// The price list: one price in whole cents per sku.

const prices = new Map();

function set(sku, cents) {
  prices.set(sku, cents);
  return cents;
}

// Put many prices at once. Gives back how many it wrote.
function setMany(entries) {
  let written = 0;
  for (const [sku, cents] of entries) {
    prices.set(sku, cents);
    written += 1;
  }
  return written;
}

function get(sku) {
  return prices.has(sku) ? prices.get(sku) : null;
}

function has(sku) {
  return prices.has(sku);
}

function remove(sku) {
  return prices.delete(sku);
}

function skus() {
  return [...prices.keys()];
}

function size() {
  return prices.size;
}

function reset() {
  prices.clear();
}

module.exports = { set, setMany, get, has, remove, skus, size, reset };
