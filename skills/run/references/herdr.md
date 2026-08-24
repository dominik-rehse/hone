# `--all` across herdr tabs

Background for `/hone:run --all` when the session runs inside
[herdr](https://github.com/dominik-rehse/herdr). `parallel.md` sends you here
after `test "${HERDR_ENV:-}" = 1` passed.

The tabs change **where** each run executes, nothing else. This session becomes
**MAIN**: it plans the order, spawns the workers, watches the repository, and
reports. Each Plan runs in a **SUB** tab, a fresh Claude Code session that
executes the ordinary `/hone:run <change>` loop, gates and all. Every law of
`run` holds unchanged inside each SUB.

The claim and the locks already make concurrent sessions safe. `worktree.sh add`
is the atomic claim (exit 4 = someone else owns it). Lands serialize under one
cross-session lock. The tabs build on that, they do not replace it.

The installed `herdr` binary is the authority for syntax. When a command here
fails to parse, run the group without a subcommand (`herdr tab`, `herdr agent`,
`herdr pane`). Follow what the installed version prints. Never run bare `herdr`
for discovery, because that launches the TUI.

Most herdr commands return JSON. Read every identifier from those responses.
Never predict an ID, and never derive one from sidebar order.

## Caller context

herdr injects the calling pane's context:

```bash
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

`$HERDR_TAB_ID` is MAIN's own tab.

## Names

Derive `<short>` first: a very short lowercase name for this set of runs, at
most 8 characters. Take it from the repo name or the area the Plans share. Names
must stay short enough to read in a tab bar. MAIN's tab becomes `MAIN:<short>`,
and each worker tab `SUB:<short>:<change>`.

Two namespaces, two rules:

- **Tab labels** are free text. `/` and `:` are fine, so
  `SUB:mail:auth/refresh-token` is a valid label.
- **Agent names** must match `[a-z][a-z0-9_-]{0,31}` and be unique among live
  agents. Map a change slug to its agent name: prefix `sub-`, lowercase,
  replace every character outside `[a-z0-9_-]` with `-`, truncate to 32.
  `auth/refresh-token` becomes `sub-auth-refresh-token`. On a collision after
  truncation, replace the tail with `-2`, `-3`, and so on.

The runs stay in the current workspace. A human who wants them in a workspace
of their own creates that workspace and invokes `/hone:run --all` in it, because
a session cannot move itself.

## What MAIN never does

MAIN sits in the primary tree, and the guard blocks durable edits there. That is
the design, not an obstacle:

- MAIN never builds, fixes, or consolidates a change. Everything specific to a
  Plan happens in that Plan's SUB session, including its `worktree.sh land`.
- MAIN never runs a probe or a real-environment check. Those run in the SUB tab,
  because the worktree under test lives with that SUB. The human splits a pane
  there when they need a shell.
- MAIN never writes a grant or a sign-off, and never prompts a SUB to route
  around a gate. A land gate belongs to the SUB that hit it, which discharges it
  exactly as `run` does, or escalates.
- MAIN never trusts a SUB's report. The only completion signal is the
  repository:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" landed <change>
  ```

  `landed` (exit 0) means merge commit present, and branch, worktree, and Plan
  gone. That command reads the repository, not a transcript.

MAIN may run `/hone:plan` while it waits: planning belongs in the primary tree,
and new approved Plans can join the set.

## Procedure

1. **Partition.** Apply `parallel.md`'s checklist to the whole Plan set:
   disjoint Plans run in parallel SUBs now, overlapping Plans form chains,
   foundation first. State the partition and its reason before spawning
   anything.

2. **Rename MAIN.**

   ```bash
   herdr tab rename "$HERDR_TAB_ID" "MAIN:<short>"
   ```

3. **Spawn one SUB per startable Plan.** The tab's working directory is the
   primary tree, because `/hone:run` makes its own worktree. `--no-focus` keeps
   the user where they are.

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

   `agent start` returns when the Claude session is ready for input (30 s
   default timeout). `--permission-mode auto` is what keeps the SUB unattended:
   without it, the first approval prompt stalls the run. Pass `--model` only
   when the invocation carried it.

4. **Watch.** Wait on each SUB, always in the Bash tool's background mode. Then
   poll the output file. A run outlasts the ~2 minute foreground timeout, and so
   does this wait.

   ```bash
   herdr agent wait <agent-name> --timeout 3600000
   ```

   It returns when the agent settles (`idle`, `done`, or `blocked`). A settled
   state says the SUB stopped typing, nothing more. Run the `landed` predicate
   each time one settles. If the SUB is still `working` when the wait times out,
   wait again.

   Keep a status board: one line per Plan, reprinted each time a SUB settles, a
   Plan starts, or a tab closes. Every state on it comes from what MAIN can
   verify itself:

   ```
   csv-export   landed a1b2c3d
   auth-retry   running (SUB:mail:auth-retry)
   rate-limit   queued (waits on auth-retry)
   pdf-export   needs human — proof gate, tab kept
   ```

   `landed` comes from the predicate alone. `running` comes from the agent
   state, and `needs human` from the tail read. When you relay a SUB's own
   progress line, mark it as the SUB's claim ("SUB reports verify …"), never
   as MAIN's knowledge.

   - `landed`: close that SUB tab, report the land, and start whatever Plan was
     waiting on it.
   - `pending`: the SUB stopped mid-loop. Read its tail to classify, never to
     adopt its work:

     ```bash
     herdr agent read <agent-name> --source recent-unwrapped --lines 120
     ```

     - **A land gate fired (exit 7 or 8) and the SUB stopped there.** The SUB
       discharges its own gates. A stop means it could not. Either the check is
       out of its reach, or the diff is not what the Plan asked for. Notify the
       human, then wait.
     - **A question or an approval prompt.** Notify the human, name the tab,
       wait. Never answer for them.
     - **Blocked-unresolvable or genuinely ambiguous** (`run`'s stop points 1
       and 2): report it and leave the tab open. The worktree and the tab are
       the evidence.
   - A SUB whose `worktree.sh add` exited 4 found the change claimed by another
     session: it skips, and MAIN reports the skip.

   The notification, whatever the reason:

   ```bash
   herdr notification show "hone: <change> needs you" \
     --body "Tab SUB:<short>:<change>: <what the SUB is waiting for>" \
     --sound request
   ```

   Name the tab in the body, so the human goes to the SUB, not to MAIN. Probes
   and proofs run from the SUB tab. The grant and attest helpers stay in the
   human's own terminal, as always.

5. **Chains.** Start a dependent Plan only when its predecessor's `landed`
   predicate prints `landed`. Never on the SUB's word, never on an idle state
   alone: "fully landed" is a property of the repository.

6. **Global consolidate.** When every Plan has landed, spawn one last SUB tab,
   `SUB:<short>:consolidate`. Prompt it to run the global consolidate pass from
   `parallel.md`: a `consolidate-critic` over the combined result. It lands
   any accepted cuts through a worktree change of its own. Close its tab when
   that lands, or when it reports nothing to cut.

7. **Report.** Print the final status board. Per Plan: landed (with the merge
   commit) or stopped (with the blocker and the tab left open). Name the tabs
   closed and the tabs kept.

## Closing a SUB tab

```bash
herdr tab close <tab-id>
```

Only after `landed` printed `landed`, and only for tabs this session created. A
stopped SUB keeps its tab for the same reason a failed land keeps its worktree:
it is evidence, and the human resumes there.
