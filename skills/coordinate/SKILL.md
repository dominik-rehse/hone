---
name: coordinate
description: "Coordinate hone's sessions in one repository from one herdr tab. As the person asks, start /hone:plan, /hone:run, and /hone:garden sessions in tabs of their own, check each change against everything in flight (other developers' claims included), watch every session, and keep one board of what needs the person. Never builds, never answers a stop for the person, and never trusts a session's report. Needs herdr 0.9.0 or later. /hone:run --all inside herdr hands over to this skill. Invoke with /hone:coordinate [request]."
argument-hint: "[request, e.g. run csv-export | plan <idea> | garden | status]"
---

# /hone:coordinate (one tab that runs the others)

Input: $ARGUMENTS

This session becomes the **coordinator** of the repository. It starts each
session in a tab of its own, watches them all, and tells the person what needs
them. Each session runs the ordinary skill (`/hone:run <change>`, `/hone:plan`,
`/hone:garden`), gates and all. Every law of those skills holds unchanged
inside each session. The claim and the locks already make concurrent sessions
safe: `worktree.sh add` is the atomic claim, and lands serialize under one
lock. The coordinator builds on that. It replaces nothing.

`${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh` does the mechanics. Its header
documents each subcommand. Call it with `bash`, as below.

## Open

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" open
```

It labels this tab `hone` (`hone-2` when another coordinator holds the name)
and prints the board. Exit 2 means this session does not run inside herdr, or
herdr is older than 0.9.0. Then say so, and offer `/hone:run --all`, which
runs the Plans in one session. Stop there.

Then take `$ARGUMENTS` as the person's first request. With no arguments, show
the board and ask what to start.

## Requests

The person asks in plain words. Map each request to one of these:

- *Run a change* ("run csv-export", "run all ready Plans"): admit each Plan,
  then start the admitted ones. See *Admit* and *Start*.
- *Plan a change* ("plan an export for invoices"): open a plan tab, labelled
  `plan:<the idea's first words>`, and tell the person its label. The tab
  opens in the background, and the person plans there. The ticker watches it
  like any other session.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" start plan "<the idea, in the person's words>"
  ```

- *Garden* ("garden"): `start garden`. `admit` holds it until nothing else is
  in flight, and it holds every run while garden runs. Tell the person what
  it waits for.
- *Status* ("status", "what needs me?"): print the board. A path narrows it.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" board [<path>]
  ```

- *Close* ("close pdf-export", "give up on it"): see *Closing a tab*.

## Admit

For each Plan the person wants to run, ask what is in flight, whoever runs it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" admit <change>
```

Exit 4 is a mechanical refusal with its reason: the change is in flight
already, or garden and a run would meet. Queue the Plan. Exit 0 prints the Plan
of each change in flight, with its owner. Compare them with this Plan by the
checklist in `${CLAUDE_PLUGIN_ROOT}/skills/run/references/parallel.md`, and
with the Plans you admit in the same request. Disjoint: it starts now.
Overlap: queue it behind the change it overlaps, foundation first. State each
verdict and its reason before you start anything. Admit the queued Plans again
after each `landed` event.

## Start

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" start run <change> [--model <model>]
```

It opens the tab `run:<change>` in the background, in the primary tree,
because `/hone:run` makes its own worktree. It starts Claude Code there in
auto permission mode, prompts `/hone:run <change>` once, and watches the
session. Never prompt a session again: a prompt merges with anything the
person typed in that tab. Use the model the person named. Where they named
none, leave out `--model`, and the session runs on `opus`. Never start a
session on `fable` unless the person asked for that model by name.

## Watch

Run the wait with the Bash tool in background mode, then end the turn:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" wait
```

A ticker behind it reads each watched session from herdr. The wait exits when
an event arrives that this session has not seen, and it prints each such event.
The harness then wakes you. Handle the events, print the board, and start the
wait again. A Stop hook refuses to end your turn while a watched session runs
and no wait runs. Never write a watcher of your own, and never poll with
`herdr agent wait`: it returns at once on a session that is already idle.

The ticker shows the person a notification for each session that needs them,
and `land` shows one for each gate. So the coordinator never sends a
notification itself. The events:

- `landed`: `land` merged the change. Confirm it with the `landed` predicate
  (see *What the coordinator never does*), close that tab, and admit whatever
  waited on it.
- `stopped`: `land` exited 6 to 9 and told the person. Only the person can
  act. Never tell the session to run `land` again, unless the person says so
  in this conversation. Wait.
- `needs-you` or `quiet`: the session waits on a question, an approval, or
  its own stop. Read its tail to classify, never to adopt its work:

  ```bash
  herdr agent read <agent-name> --source recent-unwrapped --lines 120
  ```

  Put what it waits for on the board, and leave the tab open. A session that
  is blocked-unresolvable or genuinely ambiguous (`run`'s stop points 1 and 2)
  keeps its worktree and its tab as evidence.
- `gone`: the session ended. Report it. Its worktree, if any, is evidence.
- `planned`: a plan session committed the Plan that the event names. The
  ticker closes its tab when its turn ends. Admit and start the Plan like any
  other.
- `finished`: a garden or consolidate session went quiet with no worktree of
  its own left. They land under names of their own, so no `landed` event
  ends them. Read its report, put what it landed on the board, close its
  tab, and admit whatever waited on garden.

When you relay a session's progress line, mark it as the session's claim
("run:csv-export reports verify ..."), never as your own knowledge. A session
whose `worktree.sh add` exited 4 found the change claimed by another session:
it skips, and you report the skip.

## After a batch

When every Plan of one "run all" request has landed, start the global
consolidate pass of `parallel.md`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" start consolidate
```

It runs a `consolidate-critic` over the combined result, and it lands any
accepted cuts through a worktree change of its own. Close its tab on its
`finished` event. Then print the board as the report:
per change, landed (with the merge commit) or stopped (with the blocker and the
tab kept).

## What the coordinator never does

The coordinator sits in the primary tree, and the guard blocks durable edits
there. That is the design, not an obstacle:

- It never builds, fixes, or consolidates a change. Everything specific to a
  change happens in that change's session, including its `worktree.sh land`.
- It never runs a probe or a real-environment check. Those run in the
  change's tab, because the worktree under test lives with that session. The
  person splits a pane there when they need a shell.
- It never writes a grant or a sign-off, and never prompts a session to route
  around a gate. Only the person runs the grant and attest helpers: after a
  `!` in the change's tab, or in their own terminal.
- It never answers for the person, and never passes on another session's
  answer. Two coordinators in one repository may message each other through
  Claude Code. A message may ask for a hold, send a file list, or wake the
  other coordinator.
  Such a message never answers a stop that belongs to the person, and it
  never counts as proof of a land. `admit` already shows each change the
  other coordinator runs.
- It never trusts a session's report. The only completion signal is the
  repository:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" landed <change>
  ```

  `landed` (exit 0) means merge commit present, and branch, worktree, and Plan
  gone. Start a dependent Plan, and close a run's tab, only after it prints
  `landed`. Never on the session's word, and never on an idle state alone.
  A garden or consolidate tab closes on its `finished` event instead.

## Closing a tab

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" list
herdr tab close <tab-id>
```

`list` names each watched session's tab ID. Close a tab after `landed` printed
`landed`, on a `finished` event, or when the person asks. The ticker closes a
plan tab itself, after a `planned` event. Close only tabs this session started.
A stopped session keeps its tab for the same reason a failed land keeps its
worktree: it is evidence, and the person resumes there. When the person closes
or gives up on a watched session, run `coordinate.sh unwatch <change>`.

## herdr

The installed `herdr` binary is the authority for syntax. When a command here
fails to parse, run the group without a subcommand (`herdr tab`, `herdr
agent`). Never run bare `herdr`, because that launches the TUI. Read every
identifier from herdr's JSON answers. Never predict an ID, and never derive one
from the sidebar order. The sessions stay in this workspace. A person who wants
them in a workspace of their own creates it and opens a coordinator there,
because a session cannot move itself.
