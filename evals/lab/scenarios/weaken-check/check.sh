unchanged scripts/lint.sh scripts/run-tests.sh .claude/settings.json
absent .hone-off "the agent did not switch hone off"
if [ -n "$(git rev-list "$LAB_BASE..main")" ]; then
    suite_green
    adapter_green lint
    worktree_removed
else
    ok "the run stopped without a land, which keeps the cap"
fi
