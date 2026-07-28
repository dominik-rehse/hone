# Reference

The complete control surface: commands, configuration files, hooks, land
gates, exit codes, adapters, and layout. Everything else links here; when a
detail on this page and prose elsewhere disagree, this page wins. Why the
pieces exist is covered in [`model.md`](model.md).

## Commands

Slash commands, in the order a change flows:

- `/hone:plan <change>` — write and commit the Plan for one change, checked by
  the `plan-critic` while you are present. The only manual step.
- `/hone:run <change>` — execute the Plan unattended: worktree, build,
  verify, consolidate, review, land. `/hone:run --all` runs every ready Plan.
- `/hone:garden` — scan the repo for stale docs, dead code, and redundant
  tests between changes, and land the safe deletions. Run it from cron/CI as
  `claude -p "/hone:garden"`.

`worktree.sh` (in the plugin's `scripts/` directory) does the mechanical git
work. The loop calls it; you can too:

- `worktree.sh status` — the state of everything on this page in one screen:
  hooks on or off, adapters present, policy files and whether they are
  committed, pending Plans, worktrees in flight, grants and sign-offs, and
  whether the settings deny rules are installed.
- `worktree.sh add <change>` — create `.worktrees/<change>` on branch
  `hone/<change>`. Creating it is what claims the change; a second `add` of
  the same name fails.
- `worktree.sh verify` — run the full test suite, serialized against other
  sessions. The only sanctioned way to run `--all` by hand.
- `worktree.sh land <change>` — merge the branch into the primary tree,
  re-run the suite there, and clean up. Runs the land gates first.
- `worktree.sh remove <worktree-path>` — remove a worktree hone created, and
  its branch if fully merged.
- `worktree.sh landable` — list worktrees whose branch is ahead of the
  primary branch.
- `worktree.sh grant <change> "who/why"` — record your authorization for one
  irreversible change (writes `.hone-grant/<change>`, stamped with your git
  user and the time). **For you, in your own terminal** — the `bash-guard`
  denies it to the agent.
- `worktree.sh attest <change> "what you ran"` — record your sign-off that
  the real-environment check ran (writes `.hone-proof/<change>`, stamped with
  the branch tip, your git user, and the time). Also denied to the agent.

## Configuration files

*Committed project policy* — shared, versioned, reviewed like any other file:

- `.hone-durable-paths` — paths the guard protects beyond the built-in
  `src/ tests/ docs/ db/ scripts/`. One entry per line, `#` comments: a
  directory (`deploy/`) or an exact file (`tsconfig.json`). It can only add
  paths, never remove built-ins.
- `.hone-irreversible-paths` — path globs that make a change count as
  irreversible, beyond the built-in signals (destructive SQL in a migration
  or `db/` file, a deletion under `db/`). One glob per line, `#` comments.
  The pre-0.19 name `.hone-consequential-paths` still works.

*Per-developer* — gitignored, never checked in:

- `.hone-off` — turn off every hook, for a quick manual edit outside the
  loop. Delete it when done. The `bash-guard` refuses to let the agent create
  it.
- `.hone-grant/<change>` — your authorization for one irreversible change.
  Its text lands in the merge commit body. Delete the file to revoke. Written
  by `worktree.sh grant`, or by hand (say who, when, and why).
- `.hone-proof/<change>` — your sign-off that the real-environment check for
  one change ran. It must contain the commit hash it applies to (short or
  full); after new commits it no longer counts. Written by
  `worktree.sh attest`, or by hand.

Two environment variables tune the cross-session locks:
`HONE_LAND_LOCK_TIMEOUT` (seconds a land or full-suite run waits for the
lock, default 600) and `HONE_SUITE_LOCK_TIMEOUT` (seconds the gate's
pre-land full run waits, default 30).

## Hooks

All disabled at once by `.hone-off`. A project with no `scripts/run-tests.sh`
is never gated, and enforcement assumes code lives under `src/<area>/`.

- *guard* (PreToolUse on Write/Edit) — two rules. In the primary tree, no
  edits to the protected paths at all: that work belongs in a worktree,
  landed by a merge. Anywhere, no new file under `src/` unless a test for it
  exists (test files themselves are always writable).
- *bash-guard* (PreToolUse on Bash) — tamper resistance. Denies commands that
  would disable the gate (`--no-verify`, `core.hooksPath`, creating
  `.hone-off`) or write a grant or proof sign-off (those are the human's).
  Asks before commands that modify a protected artifact (an adapter, a hook,
  settings, a policy file) or move HEAD in the primary tree. It is a
  deterrent, not a sandbox: it closes the obvious shell routes; the
  settings.json deny rules (see *Install* in the README) close the file-tool
  routes.
- *gate* (Stop) — runs `scripts/run-tests.sh`, plus `scripts/typecheck.sh`
  and `scripts/lint.sh` when they exist, and blocks the turn on any failure.
  With uncommitted `src`/`tests` changes it runs the fast unit tier; on a
  clean `hone/<change>` branch it runs the full suite (the pre-land check).
- *nag* (Stop, advisory) — hygiene findings as a visible message, never a
  block: a Plan that survived its landing, an oversized or orphan Note, a
  broken `Governs:` link, a merged `hone/*` branch left behind, a change
  about to land that deletes nothing, a `type: project` entry in the
  harness's own memory store.
- *session-start* — injects the workflow rule from the plugin, and warns
  when the test adapter, the `src/` layout, or the settings deny rules are
  missing.

## Land gates

`worktree.sh land` refuses two kinds of change until a human acts. Both
checks run before the merge, so a refused change never touches the trunk, and
the worktree stays for inspection.

- *Authority gate (exit 8)* — the diff is irreversible (see
  `.hone-irreversible-paths` above for the signals). Landing it needs your
  grant: review the diff, then `worktree.sh grant <change> "who/why"`, then
  re-run land. The grant text is recorded in the merge commit body.
- *Proof gate (exit 7)* — a commit on the branch carries a
  `Proof: real-environment` trailer (copied from the Plan), meaning no
  in-repo test can prove the change; a browser journey, canary, or deployed
  check has to. Landing it needs one of: a green `scripts/proof.sh` (see
  *Adapters*), or your sign-off after running the check yourself:
  `worktree.sh attest <change> "what you ran"`.

The agent never writes a grant or sign-off and never runs the helpers; the
`bash-guard` denies every route. When a gate fires during an unattended run,
the run stops and reports — that is the intended behavior, not a failure.

## Exit codes

`worktree.sh land`:

| Exit | Meaning |
|------|---------|
| 0 | landed and green |
| 2 | usage or repo-state error (missing branch, detached HEAD) |
| 5 | lock timeout — another land or full-suite run held the lock |
| 6 | suite red after the merge — rolled back, worktree kept |
| 7 | proof gate — real-environment proof missing |
| 8 | authority gate — irreversible change without a grant |
| 9 | merge conflict — aborted, tree restored, branch kept |

What to do at each code, in detail:
[`skills/run/references/land.md`](../skills/run/references/land.md).

Other subcommands: `add` exits 4 when the change is already claimed by
another run (0 created, 2 error); `remove` exits 3 when the path is not one
hone created (0 removed, 2 error); `verify` passes through the adapter's exit
(2 setup error, 5 lock timeout).

## Adapters

One script per job, all under the project's `scripts/`; the gate and the loop
call them so hone itself stays language-agnostic.

- `run-tests.sh` — required. Unit tier by default, `--all` for every tier,
  `<files...>` for specific files. Contract and per-ecosystem templates:
  [`templates/run-tests/README.md`](../templates/run-tests/README.md).
  Installed by `setup.sh`.
- `typecheck.sh`, `lint.sh` — optional, one line each, run by the gate when
  present.
- `proof.sh` — optional; proves a change in the real environment for the
  proof gate. Invoked as `proof.sh <change>` from the change's worktree.
  Contract and templates:
  [`templates/proof/README.md`](../templates/proof/README.md).

## Project layout

```
repo/                            # the primary tree: a merge target, never a workspace
├── src/<area>/                  # code + tests (thing.ts / thing.test.ts, thing.py / test_thing.py)
├── docs/
│   ├── decisions/<topic>.md     # one present-tense decision + why, per topic
│   ├── notes/<area>.md          # optional per-area map + one invariant, size-capped
│   └── open-questions.md        # bets only running code can settle
├── scripts/run-tests.sh         # the test adapter (plus optional typecheck/lint/proof)
├── .plans/<change>.md           # tracked; written at plan, deleted at consolidate
├── .plans/<change>/             # optional reference files for the Plan
├── .worktrees/<change>/         # gitignored; one per change in flight
├── .hone-durable-paths          # committed policy (optional)
├── .hone-irreversible-paths     # committed policy (optional)
└── .claude/settings.json        # enables the plugin; deny rules for the adapters
```

The plugin itself:

```
hone/
├── rules/workflow.md            # injected at session start
├── skills/{plan,run,garden}/    # the three commands; run/references/ loads on demand
├── hooks/                       # guard, bash-guard, gate, nag, session-start
├── scripts/{worktree,setup}.sh
├── agents/                      # plan-critic, consolidate-critic
├── templates/{run-tests,proof}/ # adapter contracts and templates
└── evals/                       # known-good answers for the critics and the loop
```

## What writes what

W = writes · M = amends · P = prunes/deletes · R = reads · — = untouched

| Operation   | .plans/ | code | tests | decisions/ | notes/ | open-q | .git |
|-------------|---------|------|-------|------------|--------|--------|------|
| plan        | W       | —    | —     | —          | —      | (W)    | W    |
| build       | R/P     | W    | W     | —          | —      | —      | —    |
| verify      | —       | R    | R     | R          | R      | R      | —    |
| consolidate | P       | —    | P     | W/M        | W/M    | M      | —    |
| land        | —       | —    | —     | —          | —      | —      | W    |
| garden      | P       | P    | P     | P          | P      | P      | W    |

Notes on the rarer cells: plan's `(W)` on open questions covers only a new
question the Plan surfaces, and its `.git` write is the commit of the Plan
and its references on the trunk. build's `.plans/` prune is a reference
promoted out (`git mv`'d next to the test that reads it — build is the only
step that writes tests). consolidate's `.plans/` prune is the `git rm` of the
Plan and any references build did not promote. garden is not part of a
change: it is the standalone maintenance loop, and every column it touches is
a deletion.
