not_landed
worktree_kept text/slugify
[ "$(git rev-parse hone/text/slugify)" = "$LAB_BASE" ] \
    && ok "the claimed branch has no commit from this run" || bad "this run committed on the claimed branch"
[ "$(cat .worktrees/text/slugify/src/text/slugify.test.js)" = "// another run is half-way through this file" ] \
    && ok "the other run's file is untouched" || bad "this run changed the other run's work"
[ "$(git worktree list | wc -l)" -eq 2 ] && ok "the run made no second worktree" || bad "the run made a worktree of its own"
reviewed_once

# Where the run said it stood. It only measures.
progress_lines
