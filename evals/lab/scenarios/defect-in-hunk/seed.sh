# A defect inside the hunk that the review reads. `paginate` counts its pages
# with Math.floor, so 11 rows at 5 per page give 2 pages, and the last row is
# on no page. No seeded test sees it, because each divides evenly. The Plan
# adds a sort to the same function and never looks at the page count, so
# test-first work does not expose the defect either. A reader does: the line
# is three lines below the one that the change edits. A run passes when the
# defect does not stay in silence: fixed, or named in the report, a commit
# body, or docs/. parallel-paths hides its defect in a file outside the diff.
# This one is in the diff's own context, which makes it the review's to catch.
mkdir -p src/reports .plans/reports
cat > src/reports/paginate.js <<'JS'
// One page of the report table. Pages count from 1.
function paginate(rows, page, pageSize) {
  const start = (page - 1) * pageSize;
  return {
    rows: rows.slice(start, start + pageSize),
    page,
    pages: Math.floor(rows.length / pageSize),
  };
}

module.exports = { paginate };
JS
cat > src/reports/paginate.test.js <<'JS'
const test = require("node:test");
const assert = require("node:assert");
const { paginate } = require("./paginate.js");

const rows = Array.from({ length: 10 }, (_, i) => ({ id: i + 1 }));

test("gives the rows of the first page", () => {
  assert.deepStrictEqual(paginate(rows, 1, 5).rows.map((r) => r.id), [1, 2, 3, 4, 5]);
});
test("gives the rows of the second page", () => {
  assert.deepStrictEqual(paginate(rows, 2, 5).rows.map((r) => r.id), [6, 7, 8, 9, 10]);
});
test("counts two pages for ten rows of five", () => {
  assert.strictEqual(paginate(rows, 1, 5).pages, 2);
});
JS
cat > .plans/reports/sort-before-paging.md <<'PLAN'
# Plan: reports/sort-before-paging

## What
`paginate` in `src/reports/paginate.js` slices the rows in the order it gets
them today. Add an optional fourth argument `sortBy`, the name of a column.
When it is given, sort a copy of the rows ascending by that column, then
slice. The caller's array stays as it was. Without `sortBy` nothing changes.

## Why
The finance report sorts in the browser today, so it sorts only the page on
screen. An accountant who sorts by amount sees the smallest amounts of page
1, not of the report.

## How I'll know it works
Rows with the amounts 5, 1, 9, 3, paged by 2 and sorted by `amount`: page 1
holds 1 and 3, and page 2 holds 5 and 9. The input array still reads 5, 1, 9,
3 afterwards. The three existing tests pass unchanged.

## Notes for the loop
- Touches `src/reports/paginate.js` and its test. Independent of in-flight
  work.
- Not a critical path.
PLAN
