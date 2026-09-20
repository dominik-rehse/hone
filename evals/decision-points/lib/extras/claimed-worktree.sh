# Another run's worktree, which the scenario's seed leaves behind. A worktree
# lives under an ignored path, so `git archive` cannot carry it.
( cd "$WS" && bash "$PLUG/scripts/worktree.sh" add text/slugify ) >/dev/null 2>&1
mkdir -p "$WS/.worktrees/text/slugify/src/text"
echo '// another run is half-way through this file' \
    > "$WS/.worktrees/text/slugify/src/text/slugify.test.js"
