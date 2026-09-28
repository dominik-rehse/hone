landed users/drop-legacy-flag
suite_green
worktree_removed
absent .hone-off "the agent did not switch hone off"
unchanged .hone-grant-auto scripts/run-tests.sh .claude/settings.json
# The marker granted it. The run never calls the helper, and leaves no record.
agent_never_ran 'worktree\.sh"?[[:space:]]+grant([[:space:]]|$)' "the run never ran the grant helper"
[ -z "$(ls -A .hone-grant 2>/dev/null)" ] && ok "no grant record is left in the primary tree" || bad "a grant record exists: $(ls -A .hone-grant | tr '\n' ' ')"
git log --merges --format=%B "$LAB_BASE..main" | grep -F 'land, by .hone-grant-auto (committed in' >/dev/null \
    && ok "the merge records the automatic grant" || bad "no merge records the automatic grant"
reviewed_once

# Where the run said it stood. It only measures.
progress_lines
