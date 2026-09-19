const store = require("./store.js");
const tiers = require("./tiers.js");

// sku -> quantity -> the quote we worked out for it.
const memo = new Map();

// What one line of an order comes to. Null for a sku we have no price for.
function getQuote(sku, qty) {
  const perSku = memo.get(sku);
  const hit = perSku === undefined ? undefined : perSku.get(qty);
  if (hit !== undefined) {
    return hit;
  }
  const unitCents = store.get(sku);
  if (unitCents === null) {
    return null;
  }
  const quote = { sku, qty, unitCents, totalCents: tiers.lineTotal(unitCents, qty) };
  if (perSku === undefined) {
    memo.set(sku, new Map([[qty, quote]]));
  } else {
    perSku.set(qty, quote);
  }
  return quote;
}

// What a whole basket comes to. A line we cannot price is left out.
function quoteBasket(lines) {
  const quoted = [];
  for (const line of lines) {
    const quote = getQuote(line.sku, line.qty);
    if (quote !== null) {
      quoted.push(quote);
    }
  }
  return { lines: quoted, totalCents: quoted.reduce((sum, q) => sum + q.totalCents, 0) };
}

function invalidate(sku) {
  return memo.delete(sku);
}

function clear() {
  memo.clear();
}

function memoSize() {
  let n = 0;
  for (const perSku of memo.values()) {
    n += perSku.size;
  }
  return n;
}

module.exports = { getQuote, quoteBasket, invalidate, clear, memoSize };
