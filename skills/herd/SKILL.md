---
name: herd
description: "Orchestrate /hone:run across herdr tabs. This session becomes MAIN: it partitions the ready Plans, spawns one fresh Claude Code session per Plan in its own SUB tab, and starts a dependent Plan only when the repository shows its predecessor fully landed. MAIN never builds, never runs a probe, and never writes a grant or sign-off; everything plan-specific happens in a SUB tab, and a SUB tab closes only when its change has landed. Requires a herdr-managed pane. Invoke with /hone:herd [changes... | --all] [--model <model>] [--workspace]."
argument-hint: "[changes... | --all] [--model <model>] [--workspace]"
disable-model-invocation: true
---

# /hone:herd (drive many runs from a MAIN tab)

Input: $ARGUMENTS

`herd` is `/hone:run --all` spread over herdr tabs. This session is **MAIN**.
It plans the order, spawns the workers, watches the repository, and reports.
Each Plan runs in a **SUB** tab: a fresh Claude Code session that executes the
ordinary `/hone:run <change>` loop, gates and all. herd adds topology only.
Every law of `run` holds unchanged inside each SUB.

The claim and the locks already make concurrent sessions safe. `worktree.sh
add` is the atomic claim (exit 4 = someone else owns it). Lands serialize
under one cross-session lock. herd builds on that, it does not replace it.

## Preconditions

- Run `test "${HERDR_ENV:-}" = 1`. If it fails, say that this session is not
  inside herdr and stop. Never control a herdr session from outside it.
- `scripts/run-tests.sh` must exist, as for `run`. Without the adapter, point
  the user at `/hone:setup` and stop.
- Resolve the Plan set exactly as `run` resolves `$ARGUMENTS`: named changes,
  `--all` for every ready Plan, or ask when the input is empty and ambiguous.

## Arguments

- `--model <model>` sets the model for every SUB session (it becomes
  `claude --model <model>`). Without it, SUBs use the Claude Code default.
- `--workspace` selects the dedicated-workspace pattern (below).
- Everything else is the Plan set, as in `run`.

## The two patterns, and naming

Derive `<short>` first: a very short lowercase name for this herd (at most 8
characters), from the repo name or the area the Plans share. Names must stay
short enough to read in a tab bar.

- **Default (shared workspace)**: work in the current workspace. Rename this
  tab to `MAIN:<short>`. Label each worker tab `SUB:<short>:<change>`.
- **`--workspace` (dedicated workspace)**: the herd owns a whole workspace.
  The human has to start this pattern, because a session cannot move itself
  into a new workspace. If the current workspace holds any tab besides this
  one, stop and instruct the user. They create a fresh workspace (herdr UI,
  or `herdr workspace create --cwd <repo>`) and start Claude Code in it.
  There they invoke this command again. Once the herd has the workspace to
  itself, rename the workspace to `<short>`, this tab to `MAIN:<short>`, and
  label each worker tab `SUB:<change>`.

Tab labels take `/` and `:` freely, so the change slug appears verbatim.
herdr **agent names** do not. The name mapping and every exact command live
in `${CLAUDE_PLUGIN_ROOT}/skills/herd/references/herdr.md`. Read that file
before the first herdr command.

## What MAIN never does

MAIN sits in the primary tree, and the guard blocks durable edits there. That
is the design, not an obstacle:

- MAIN never builds, fixes, or consolidates a change. Everything specific to
  a Plan happens in that Plan's SUB session, including its `worktree.sh land`.
- MAIN never runs a probe or a real-environment check. Those run in the SUB
  tab, because the worktree under test lives with that SUB. The human splits
  a pane there when they need a shell.
- MAIN never writes a grant or a sign-off, and never prompts a SUB to route
  around a gate. Exits 7 and 8 are the human's, exactly as in `run`.
- MAIN never trusts a SUB's report. The only completion signal is
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" landed <change>`
  printing `landed` (exit 0): merge commit present, branch, worktree, and
  Plan gone. That command reads the repository, not a transcript.

MAIN may run `/hone:plan` while it waits: planning belongs in the primary
tree, and new approved Plans can join the herd.

## Procedure

1. **Partition.** Read
   `${CLAUDE_PLUGIN_ROOT}/skills/run/references/parallel.md` and apply its
   checklist to the whole Plan set: disjoint Plans run in parallel SUBs now,
   overlapping Plans form chains, foundation first. State the partition and
   its reason before spawning anything, exactly as `--all` does.
2. **Rename.** Apply the naming above to this tab (and the workspace, when
   the herd owns it).
3. **Spawn.** For each startable Plan: create the SUB tab, start a Claude
   Code agent in it with `--permission-mode auto` (plus `--model` when
   given), and submit `/hone:run <change>`. Command sequence:
   `references/herdr.md`.
4. **Watch.** Wait on each SUB with `herdr agent wait`, always in the Bash
   tool's background mode: a run outlasts the ~2 minute foreground timeout.
   Each time a SUB settles, run the `landed` predicate:
   - `landed`: close that SUB tab, report the land, and start whatever Plan
     was waiting on it.
   - `pending`: the SUB stopped mid-loop. Read its tail
     (`herdr agent read`) to classify, never to adopt its work:
     - **A land gate fired (exit 7 or 8).** Send a herdr notification to the
       human. It names the SUB tab, and the check or grant the gate printed.
       The human proves or grants, then re-runs land in that SUB. MAIN waits.
     - **A question or an approval prompt.** Notify the human, name the tab,
       wait. Never answer for them.
     - **Blocked-unresolvable or genuinely ambiguous** (run's stop points 1
       and 2): report it and leave the tab open. The worktree and the tab
       are the evidence.
   - A SUB whose `worktree.sh add` exited 4 found the change claimed by
     another session: it skips, and MAIN reports the skip, as `--all` does.
5. **Chains.** Start a dependent Plan only when its predecessor's `landed`
   predicate prints `landed`. Never on the SUB's word, never on an idle
   state alone: "fully landed" is a property of the repository.
6. **Global consolidate.** When every Plan has landed, spawn one last SUB
   tab: `SUB:<short>:consolidate`, or `SUB:consolidate` in a dedicated
   workspace. Prompt it to run the global consolidate pass from
   `parallel.md`: a `consolidate-critic` over the combined result. It lands
   any accepted cuts through a worktree change of its own. Close its tab
   when that lands, or when it reports nothing to cut.
7. **Report.** Per Plan: landed (with the merge commit) or stopped (with the
   blocker and the tab left open). Name the tabs closed and the tabs kept.

## Closing rule

A SUB tab closes only after its change's `landed` predicate is green, or
after the consolidate SUB finishes. A stopped SUB keeps its tab for the same
reason a failed land keeps its worktree: it is evidence, and the human
resumes there. Close only tabs this herd created.
