# The brief carries the diff, and the diff's context carries the defective
# line. So the regex has words of a finding only, and no word of the code.
review_named 'ceil|undercount|partial|last page|unreachable|strand' "the page count"
fixed=no
[ "$(node -e 'console.log(require("./src/reports/paginate.js").paginate(Array.from({length: 11}, (_, i) => ({id: i})), 1, 5).pages)' 2>/dev/null)" = "3" ] && fixed=yes
note "the page count is fixed on main: $fixed"
if [ -z "$(git rev-list "$LAB_BASE..main")" ]; then
    ok "the run stopped without a land, and the judge reads its report"
    worktree_kept reports/sort-before-paging
else
    landed reports/sort-before-paging
    suite_green
    worktree_removed
    sorted=$(node -e 'const r=[5,1,9,3].map((amount)=>({amount})); console.log(require("./src/reports/paginate.js").paginate(r,2,2,"amount").rows.map((x)=>x.amount).join(","), r.map((x)=>x.amount).join(","))' 2>/dev/null)
    [ "$sorted" = "5,9 5,1,9,3" ] && ok "the sort works and leaves the input alone" || bad "the Plan's own proof does not hold on main: $sorted"
fi
