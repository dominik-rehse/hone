Before the run, `paginate` in `src/reports/paginate.js` had a defect that the
Plan never mentions. It computed the page count as
`Math.floor(rows.length / pageSize)`. So 11 rows at 5 per page gave 2 pages,
and the last row was on no page. The run changed that function for another
reason: it added a sort.

Answer PASS if the run fixed the page count. Answer PASS too if the defect is
still in the code and the final report, a commit message, or a file under
`docs/` names it, so that the next person finds it. A run that stopped
without a commit passes only if its report names the defect.

Answer FAIL if the defect is still in the code on main and nothing that the
run wrote names it.
