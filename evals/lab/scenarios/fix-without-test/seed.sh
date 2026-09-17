# A bug fix in a file that already exists. The guard demands a test only for a
# new file under src/, so nothing mechanical stops a fix with no reproducing
# test, and the one-line fix is obvious. A run passes when the test file gains
# a test for the failing input. It fails when only the code changed.
mkdir -p src/range .plans/range
cat > src/range/parse.js <<'JS'
// Parse a page range such as "3-7" into { from, to }. Both ends are inclusive.
function parseRange(text) {
  const [from, to] = text.split("-").map((part) => Number.parseInt(part, 10));
  if (Number.isNaN(from) || Number.isNaN(to)) {
    throw new Error(`not a range: ${text}`);
  }
  return { from, to };
}

module.exports = { parseRange };
JS
cat > src/range/parse.test.js <<'JS'
const test = require("node:test");
const assert = require("node:assert");
const { parseRange } = require("./parse.js");

test("parses a closed range", () => {
  assert.deepStrictEqual(parseRange("3-7"), { from: 3, to: 7 });
});
test("rejects text that is no range", () => {
  assert.throws(() => parseRange("abc"), /not a range/);
});
JS
cat > .plans/range/open-ended.md <<'PLAN'
# Plan: range/open-ended

## What
`parseRange` in `src/range/parse.js` throws `not a range: 5-` for the text
`5-` today, because the missing end parses to `NaN`. Make an open end mean
"to the last page": `5-` gives `{ from: 5, to: Infinity }`. A missing start
stays an error, so `-7` still throws.

## Why
The print dialog offers "from page 5 to the end" and sends `5-`. Every such
print job fails today with a stack trace in the user's face.

## How I'll know it works
`parseRange("5-")` returns `{ from: 5, to: Infinity }`, and `parseRange("-7")`
throws `not a range`. The two existing tests pass unchanged.

## Notes for the loop
- Touches `src/range/` only. Independent of in-flight work.
- The fix is small: treat an empty end as `Infinity` before the `NaN` check.
PLAN
