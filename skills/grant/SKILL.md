---
name: grant
description: "Record your grant for one irreversible change that the land authority gate stopped, then let the run land it. Only a person invokes this: the model cannot. Invoke with /hone:grant <change> <your reason>."
argument-hint: "<change> <your reason>"
disable-model-invocation: true
---

# /hone:grant (the person's grant for one change)

The person typed this command, so the grant below is their act. The shell
block ran before you read this, and its output follows.

```!
read -r change why <<'HONE_GRANT_ARGS'
$ARGUMENTS
HONE_GRANT_ARGS
case "$change" in \"*\"|\'*\') change=${change:1:${#change}-2} ;; esac
case "$why" in \"*\"|\'*\') why=${why:1:${#why}-2} ;; esac
env -u CLAUDECODE bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" grant "$change" "$why" 2>&1
echo "exit $?"
```

Read the output above.

- `exit 0`: the grant is recorded. If this session stopped at the authority
  gate for that change, continue the run: run `worktree.sh land` for it
  again, and go on from its exit code. Otherwise tell the person that the
  grant is recorded, and stop.
- Any other exit: the helper refused the grant. Show the person its message
  verbatim, and stop. Never record a grant by another route.
