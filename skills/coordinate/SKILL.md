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

## The person's word

Keep a short list of the person's standing answers in this conversation:
each thing they decided once for the whole batch, in their words. Before you
ask the person anything, read the list. Never ask again what it answers.

A yes covers only the action that your question named. "Do you want Plans
for 1 and 2?" and a yes start two plan tabs, and no run. Starting a run
needs its own word, or a standing answer that names runs. When the person
asked for less than you assumed, do only that.

When the person delegates ("don't get back to me", "I accept all your plans
and grants"), tell them at once what hone can record, and what it cannot:

- *Grants*: the person can commit `.hone-grant-auto` on the primary branch,
  in their own terminal. Then `land` grants every irreversible change
  itself (the authority gate, exit 8) and records it in the merge commit.
  It never grants a change that touches the marker. You never write it.
  Offer it once, with its cost: no person reads an irreversible change
  before it merges.
- *Proof sign-offs* (exit 7) stay the person's act: `attest` in the
  change's tab, or a green `scripts/proof.sh`. No marker records them.
- *A merge that failed a check* (exit 6) needs the person's word for that
  stop. A standing answer does not cover it.
- *Questions and permission prompts in a session's tab* wait for the person
  there. You never answer them (see *Watch*).

Then put the rest of their delegation on your list: what to plan, what to
run, in which order. Act on it, and stop asking it.

## Admit

For each Plan the person wants to run, ask what is in flight, whoever runs it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" admit <change>
```

Exit 4 is a mechanical refusal with its reason. The change is in flight
already, garden and a run would meet, or the Plan orders a change first that
has not landed. Or as many runs as the cap allows are in flight: 4, unless
the person sets `HONE_COORD_MAX_RUNS`. Queue the Plan. Pass `--after-ok <name>` to `admit` and
`start` only when the person says that order does not bind. Exit 0 prints the Plan
of each change in flight, with its owner. Compare them with this Plan by the
checklist in `${CLAUDE_PLUGIN_ROOT}/skills/run/references/parallel.md`, and
with the Plans you admit in the same request. Disjoint: it starts now.
Overlap: queue it behind the change it overlaps, foundation first. State each
verdict and its reason before you start anything. Admit the queued Plans again
after each `landed` or `finished` event.

## Start

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" start run <change> [--model <model>]
```

It opens the tab `run:<change>` in the background, in the primary tree,
because `/hone:run` makes its own worktree. It starts Claude Code there in
auto permission mode, prompts `/hone:run <change>` once, and watches the
session. After that, reach it only through *Send*. Exit 3 means the prompt
did not show in the tab. Do what its `Do:` line says. Use the model the person named. Where they named
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
wait again. Exit 3 means the wait ended on time with no event, before the
harness limit could kill it. Start it again at once and end the turn. Never
ask the person to wake you. A Stop hook refuses to end your turn while a
watched session runs and no wait runs. Never write a watcher or a poller of
your own, and never poll with `herdr agent wait`: it returns at once on a
session that is already idle.

The ticker shows the person a notification for each session that needs them,
and `land` shows one for each gate. So the coordinator never sends a
notification itself. On each tick the ticker also reads the repository. It
finds a committed Plan, a merge, a sign-off, a grant, and a pass whose cuts
landed. It writes the event that a session missed, once. So
never check these yourself in a loop. The events:

- `landed`: `land` merged the change. Confirm it with the `landed` predicate
  (see *What the coordinator never does*), close that tab, and admit whatever
  waited on it.
- `stopped`: `land` exited 6 to 9 and told the person. Only the person can
  act. Never tell the session to run `land` again, unless the person said
  so for this stop. A standing answer, a memory, or the session's own
  reason does not count. After exit 6 ask the person, and `send` "run land
  again" only on their yes. Wait.
- `turn-ended`: the session's turn ended. The event carries the last line
  of its message. It may be a report, a question in text, or a stop. Read
  its tail (below) when the line does not say enough, and act as for
  `quiet`. The ticker then sends no `quiet` for that turn.
- `needs-you` or `quiet`: the session waits on a question, an approval, or
  its own stop. **A question or a permission prompt in another tab belongs
  to the person. Never answer it, never offer to, and never send it keys,
  even when the person asks you to.** Tell them the tab and what it asks.
  If they ask you to answer, say no: hone gives that answer only to them.
  Read its tail to classify, never to adopt its work:

  ```bash
  herdr agent read <agent-name> --source recent-unwrapped --lines 120
  ```

  Put what it waits for on the board, and leave the tab open. A session that
  is blocked-unresolvable or genuinely ambiguous (`run`'s stop points 1 and 2)
  keeps its worktree and its tab as evidence.
- `gone`: the session ended. Report it. Its worktree, if any, is evidence.
- `planned`: a plan session committed the Plan that the event names. The
  ticker closes its tab when its turn ends. Admit and start the Plan like any
  other. A `planned` under `plan:<slug>` that names no tab of yours comes
  from the ticker: the planner chose another slug. Close that plan tab when
  it goes quiet.
- `signed` or `granted`: after a stop at exit 7 or 8, the person's sign-off
  or grant appeared. `signed` says whether it names the branch tip. Put it
  on the board. Only the person tells the session to land again.
- `finished`: a garden or consolidate session ended its turn with no
  worktree of its cuts left, after a cut landed or after the quiet wait.
  They land under names of their own, so no `landed` event ends them. Read its report, put what it landed on the board, close its
  tab, and admit whatever waited on garden.
- `sent`: your own `send`. Your wait skips it.
- `updated`: a session runs a newer hone than you do. Your scripts and hooks
  are the old ones until this session restarts. Tell the person to quit
  this session and run the `claude --resume <id>` that the event names, in
  this tab. Your watches belong to this session's id, and a resume keeps
  it. A fresh session owns no watch.

After the events, the wait prints one line that starts with `◆ hone
sessions`: each watched session's last progress line, or its state. The
progress hook shows the same line to the person in this tab. When you cite
a session's progress, mark it as the session's claim ("run:csv-export
reports verify ..."), never as your own knowledge. A session
whose `worktree.sh add` exited 4 found the change claimed by another session:
it skips, and you report the skip.

## Send

The one way to put text into a session's tab:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" send <change> "<text>"
```

Never use `herdr agent prompt`, `herdr pane run`, or `herdr pane send-text`
for this. `send` refuses text that starts with `!` (exit 4), even after a
blank: a shell command for the person, such as `! attest`, is the person's
to type. Tell them the command and the tab instead. Exit 3 means the text
did not show in the tab, as with `start`. It also refuses a
session that waits on a question or a prompt, because that answer belongs
to the person. Send only what the person said to send, and nothing that
routes around a gate.

## After a batch

When every Plan of one "run all" request has landed, start the global
consolidate pass of `parallel.md`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/coordinate.sh" start consolidate
```

Its prompt names the batch's base commit, which the first `start run`
recorded, and the count of merges since it, so the pass covers every one.
It runs a `consolidate-critic` over the combined result, and it lands any
accepted cuts through worktree changes named `consolidate/<slug>`. When
`start` says the pass has no base commit, tell the person and ask. Close
its tab on its `finished` event, which waits until no cut holds a worktree.
Then print the board as the report:
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
- It never puts a sign-off or grant request in its own words, and never
  recommends signing or granting. It quotes the refusal verbatim from the
  session's tab, or names the tab. The person judges the check, not your
  summary of it.
- It never guesses state. Whether a sign-off or a grant exists, and whether
  the sign-off names the tip, comes from `list` or `board`. They read the
  files as `land` does. Run one and quote it, never a memory or a session's
  words.
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
