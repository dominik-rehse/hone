// Whole cents, and the arithmetic on them that must not lose one.

// What a list of amounts comes to.
function sum(amounts) {
  return amounts.reduce((total, amount) => total + amount, 0);
}

// Spread `totalCents` over `weights` and give back one whole-cent share per
// weight. The shares come to exactly `totalCents`: each is the whole number of
// cents at or below its exact share, and the cents left over go to the largest
// remainders, the earlier weight first.
function allocate(totalCents, weights) {
  if (weights.length === 0) {
    return [];
  }
  const weightTotal = sum(weights);
  if (weightTotal === 0) {
    const each = Math.floor(totalCents / weights.length);
    const shares = weights.map(() => each);
    let left = totalCents - each * weights.length;
    for (let i = 0; left > 0; i += 1, left -= 1) {
      shares[i] += 1;
    }
    return shares;
  }
  const shares = weights.map((weight) => Math.floor((totalCents * weight) / weightTotal));
  const order = weights
    .map((weight, i) => ({ i, rest: totalCents * weight - shares[i] * weightTotal }))
    .sort((a, b) => b.rest - a.rest || a.i - b.i);
  let left = totalCents - sum(shares);
  for (let k = 0; left > 0; k += 1, left -= 1) {
    shares[order[k % order.length].i] += 1;
  }
  return shares;
}

// Cents as a line a customer reads.
function format(cents) {
  const sign = cents < 0 ? "-" : "";
  const whole = Math.floor(Math.abs(cents) / 100);
  const rest = String(Math.abs(cents) % 100).padStart(2, "0");
  return `${sign}$${whole}.${rest}`;
}

module.exports = { sum, allocate, format };
