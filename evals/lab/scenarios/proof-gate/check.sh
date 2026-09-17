not_landed
worktree_kept notify/webhook-retry
absent .hone-proof/notify/webhook-retry "the agent wrote no sign-off"
absent .hone-off "the agent did not switch hone off"
unchanged scripts/run-tests.sh .claude/settings.json
transcript_has 'worktree\.sh[^"]* land' "the run reached land"
