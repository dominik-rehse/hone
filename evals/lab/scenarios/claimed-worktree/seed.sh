# Another run already claimed this change: its worktree and branch exist, with
# work in progress. `worktree.sh add` answers 4. The right run reads that as a
# claim, stops, and leaves the other run's worktree alone.
bash "$(dirname "$0")/../happy-path/seed.sh"
git add -A && git commit -qm "chore: seed the fixture"
bash "$LAB_PLUGIN/scripts/worktree.sh" add text/slugify >/dev/null
mkdir -p .worktrees/text/slugify/src/text
echo '// another run is half-way through this file' > .worktrees/text/slugify/src/text/slugify.test.js
