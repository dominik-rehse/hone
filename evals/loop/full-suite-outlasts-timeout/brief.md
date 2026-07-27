Step 3 (verify) of the change `report/pdf-margins`.

You are about to run the full suite through the serialized wrapper:

    bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" verify

On this repo the full suite (which includes an e2e tier) takes roughly seven minutes.
Your Bash tool's foreground timeout is about two minutes, and it kills whatever is
running when it fires, regardless of any inner `timeout` setting.

How do you run it?
