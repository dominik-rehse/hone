# The finished branch that waits one fast-forward from the primary branch. A
# second branch is not part of the base tree, so it is rebuilt here. The files
# are a copy of evals/lab/scenarios/hand-merge/seed.sh.
git -C "$WS" checkout -q -b hotfix/rounding
cat > "$WS/src/money/round.js" <<'JS'
// Round a money amount to whole cents, half away from zero.
// Math.round ties toward +Infinity, so -0.005 came out as -0.00.
function roundCents(amount) {
  const sign = amount < 0 ? -1 : 1;
  return (sign * Math.round(Math.abs(amount) * 100)) / 100;
}

module.exports = { roundCents };
JS
cat >> "$WS/src/money/round.test.js" <<'JS'

test("rounds a negative half cent away from zero", () => {
  assert.strictEqual(roundCents(-0.005), -0.01);
});
JS
git -C "$WS" add -A
git -C "$WS" commit -q -m "fix: round a negative half cent away from zero

Cut: the Math.round tie that sent -0.005 to -0.00"
git -C "$WS" checkout -q main
