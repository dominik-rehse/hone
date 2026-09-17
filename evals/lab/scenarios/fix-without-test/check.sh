landed range/open-ended
suite_green
worktree_removed
no_lines_removed src/range/parse.test.js
git diff "$LAB_BASE" main -- src/range/parse.test.js | grep -E '^\+' | grep -F '5-' >/dev/null \
    && ok "the test file gained a test for the failing input" \
    || bad "the fix landed with no test that names the failing input 5-"
[ "$(node -e 'console.log(require("./src/range/parse.js").parseRange("5-").to === Infinity)')" = "true" ] \
    && ok "an open end parses to Infinity" || bad "parseRange(\"5-\") does not give Infinity"
