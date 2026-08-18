# herdr commands for the herd

Background for `/hone:herd`. Read this before the first herdr command of a
herd. The installed `herdr` binary is the authority for syntax. When a
command here fails to parse, run the group without a subcommand (`herdr tab`,
`herdr agent`, `herdr pane`). Follow what the installed version prints.
Never run bare `herdr` for discovery, because that launches the TUI.

Most herdr commands return JSON. Read every identifier from those responses.
Never predict an ID, and never derive one from sidebar order.

## Caller context

herdr injects the calling pane's context:

```bash
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

`$HERDR_TAB_ID` is MAIN's own tab. `test "${HERDR_ENV:-}" = 1` must pass
before any of this runs.

## Names

Two different namespaces, two different rules:

- **Tab labels** are free text. `/` and `:` are fine, so
  `SUB:mail:auth/refresh-token` is a valid label.
- **Agent names** must match `[a-z][a-z0-9_-]{0,31}` and be unique among live
  agents. Map a change slug to its agent name: prefix `sub-`, lowercase,
  replace every character outside `[a-z0-9_-]` with `-`, truncate to 32.
  `auth/refresh-token` becomes `sub-auth-refresh-token`. On a collision after
  truncation, replace the tail with `-2`, `-3`, and so on.

## Rename MAIN

```bash
herdr tab rename "$HERDR_TAB_ID" "MAIN:<short>"
herdr workspace rename "$HERDR_WORKSPACE_ID" "<short>"   # dedicated workspace only
```

## Spawn one SUB

The tab's working directory is the primary tree: `/hone:run` makes its own
worktree. `--no-focus` keeps the user where they are.

```bash
out=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" \
        --cwd "<main-root>" --label "SUB:<short>:<change>" --no-focus)
```

Read `.result.tab.tab_id` and `.result.root_pane.pane_id` from `$out`, then:

```bash
herdr agent start <agent-name> --kind claude --pane <pane-id> \
  -- --permission-mode auto [--model <model>]
herdr agent prompt <agent-name> "/hone:run <change>"
```

`agent start` returns when the Claude session is ready for input (30 s default
timeout). `--permission-mode auto` is what keeps the SUB unattended: without
it, the first approval prompt stalls the run. herdr types the prompt into
the SUB's terminal, so it is a user invocation, and the user-invocation-only
marker on `/hone:run` does not refuse it.

## Watch one SUB

Always in the Bash tool's background mode, then poll the output file: a run
outlasts the ~2 minute foreground timeout, and so does this wait.

```bash
herdr agent wait <agent-name> --timeout 3600000
```

It returns when the agent settles (`idle`, `done`, or `blocked`). A settled
state says the SUB stopped typing, nothing more. The completion check is
always the repository:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" landed <change>
```

`landed` (exit 0) means fully landed. On `pending`, classify the stop from
the SUB's own screen:

```bash
herdr agent read <agent-name> --source recent-unwrapped --lines 120
```

Reading is for classification only. MAIN never continues a SUB's work, never
answers its questions, and never re-runs its commands. If the SUB is still
`working` when the wait times out, wait again.

## Notify the human

When a SUB needs the human (a land gate, a question, an approval prompt):

```bash
herdr notification show "hone: <change> needs you" \
  --body "Tab SUB:<short>:<change>: <what the SUB is waiting for>" \
  --sound request
```

Name the tab in the body, so the human goes to the SUB, not to MAIN. Probes
and proofs run from the SUB tab. The grant and attest helpers stay in the
human's own terminal, as always.

## Close a SUB tab

Only after `landed` printed `landed`, and only for tabs this herd created:

```bash
herdr tab close <tab-id>
```

A stopped SUB keeps its tab open as evidence, next to its worktree.
