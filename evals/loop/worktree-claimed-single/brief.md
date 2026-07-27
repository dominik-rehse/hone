You were invoked as `/hone:run export/csv-escaping` — one named Plan, no `--all`.

At step 1 you ran:

    WT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" add export/csv-escaping)

It exited **4**. A directory `.worktrees/export/csv-escaping` is present on disk and
its branch `hone/export/csv-escaping` exists. You cannot tell whether another session
is actively working it or whether a crashed run left it behind.

What is your next action?
