# `--all` across herdr tabs

Background for `/hone:run --all` when the session runs inside
[herdr](https://github.com/herdrdev/herdr). `parallel.md` sends you here
after `test "${HERDR_ENV:-}" = 1` passed.

The tabs change **where** each run executes, nothing else. This session becomes
**MAIN**: it plans the order, spawns the workers, watches the repository, and
reports. Each Plan runs in a **SUB** tab, a fresh Claude Code session that
executes the ordinary `/hone:run <change>` loop, gates and all. Every law of
`run` holds unchanged inside each SUB.

The claim and the locks already make concurrent sessions safe. `worktree.sh add`
is the atomic claim (exit 4 = someone else owns it). Lands serialize under one
cross-session lock. The tabs build on that, they do not replace it.

MAIN needs herdr 0.9.0 or later. `coordinate.sh watch` refuses an older one,
and then you run the Plans in this session, without tabs.

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
  around a gate. A land gate belongs to the SUB that hit it, which stops and
  hands the human the command exactly as `run` does.
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
     -- --permission-mode auto --model <model>
   herdr agent prompt <agent-name> "/hone:run <change>"
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" watch <change> <agent-name> <tab-id>
   ```

   `agent start` returns when the Claude session is ready for input (30 s
   default timeout). `--permission-mode auto` is what keeps the SUB unattended:
   without it, the first approval prompt stalls the run. Always pass `--model`.
   Use the model the invocation carried. Where the invocation carried none, use
   `opus`. Never start a SUB on `fable` unless the user asked for that model by
   name.

4. **Watch.** Run the wait with the Bash tool in background mode, then end
   the turn:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" wait
   ```

   A ticker behind it reads each watched SUB from herdr. The wait exits when
   an event arrives that this session has not seen, and it prints each such
   event. The harness then wakes you. Handle the events, then start the wait
   again. A Stop hook refuses to end your turn while a watched SUB runs and
   no wait runs. Never write a watcher of your own, and never poll with
   `herdr agent wait`: it returns at once on a SUB that is already idle.

   The ticker also shows the person a notification for each SUB that needs
   them, and `land` shows one for each gate. So MAIN never sends a
   notification itself.

   Keep a status board: one line per Plan, reprinted each time an event
   arrives, a Plan starts, or a tab closes. Every state on it comes from what
   MAIN can verify itself:

   ```
   csv-export   landed a1b2c3d
   auth-retry   running (SUB:mail:auth-retry)
   rate-limit   queued (waits on auth-retry)
   pdf-export   needs human: proof gate, tab kept
   ```

   `landed` comes from the predicate alone. When you relay a SUB's progress
   line, mark it as the SUB's claim ("SUB reports verify ..."), never as
   MAIN's knowledge. The events:

   - `landed`: `land` merged the change. Confirm it with the `landed`
     predicate above, close that SUB tab, report the land, and start
     whatever Plan waited on it.
   - `stopped`: `land` exited 6 to 9 and told the person. Only the person
     can act. Never tell the SUB to run `land` again, unless the person says
     so in this conversation. Wait.
   - `needs-you` or `quiet`: the SUB waits on a question, an approval, or its
     own stop. Read its tail to classify, never to adopt its work:

     ```bash
     herdr agent read <agent-name> --source recent-unwrapped --lines 120
     ```

     Report what it waits for on the board, and leave the tab open. Never
     answer for the person, and never pass on another session's answer. A
     SUB that is blocked-unresolvable or genuinely ambiguous (`run`'s stop
     points 1 and 2) keeps its worktree and its tab as evidence.
   - `gone`: the SUB's session ended. Report it. Its worktree, if any, is
     evidence.

   When the person closes a stopped SUB's tab or gives up on it, run
   `coordinate.sh unwatch <change>`. A SUB whose `worktree.sh add` exited 4
   found the change claimed by another session: it skips, and MAIN reports
   the skip. Probes and proofs run from the SUB tab. Only the person runs the
   grant and attest helpers: after a `!` in the SUB tab, or in their own
   terminal.

5. **Chains.** Start a dependent Plan only when its predecessor's `landed`
   predicate prints `landed`. Never on the SUB's word, never on an idle state
   alone: "fully landed" is a property of the repository.

6. **Global consolidate.** When every Plan has landed, spawn one last SUB tab,
   `SUB:<short>:consolidate`. Prompt it to run the global consolidate pass from
   `parallel.md`: a `consolidate-critic` over the combined result. It lands
   any accepted cuts through a worktree change of its own. Close its tab when
   that lands, or when it reports nothing to cut. Watch it like any other SUB.

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
