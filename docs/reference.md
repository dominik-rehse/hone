# Reference

The complete control surface: commands, configuration files, hooks, land
gates, exit codes, adapters, and layout. Everything else links here; when a
detail on this page and prose elsewhere disagree, this page wins. Why the
pieces exist is covered in [`model.md`](model.md).

## Commands

Slash commands, in the order a change flows:

- `/hone:setup` runs once per project: `scripts/setup.sh` for the mechanics,
  then a verification of the install. Author the adapter where detection fell
  short, execute every installed adapter, fix what fails, and complete the
  settings block. Interactive; run it with the human present.
- `/hone:plan <change>` writes and commits the Plan for one change, checked by
  the `plan-critic` while you are present. The only manual step.
- `/hone:run <change>` executes the Plan unattended (worktree, build, verify,
  consolidate, review, land). `/hone:run --all` runs every ready Plan.
- `/hone:herd` runs `--all` across herdr tabs, when the session runs inside
  herdr. This tab becomes `MAIN:<short>` and orchestrates. Each Plan gets a
  fresh Claude Code session in its own `SUB` tab (`--model` picks their
  model). MAIN starts a dependent Plan only when `worktree.sh landed` shows
  the predecessor landed, and closes a SUB tab only then. Probes, proofs, and
  everything else plan-specific happen in the SUB tab, never in MAIN.
  `--workspace` puts the herd in a workspace of its own, which you create and
  start it in.
- `/hone:garden` scans the repo for stale docs, dead code, and redundant tests
  between changes, and lands the safe deletions. You invoke it, as often as
  the repo needs it.

`worktree.sh` (in the plugin's `scripts/` directory) does the mechanical git
work. The loop calls it; you can too:

- `worktree.sh status` shows the state of everything on this page in one
  screen: hooks on or off, adapters present, policy files and whether they are
  committed, pending Plans, worktrees in flight, grants and sign-offs, and
  whether the settings deny rules are installed.
- `worktree.sh add <change>` creates `.worktrees/<change>` on branch
  `hone/<change>`. Creating it is what claims the change; a second `add` of
  the same name fails.
- `worktree.sh verify` runs the full test suite, serialized against other
  sessions. The only sanctioned way to run `--all` by hand.
- `worktree.sh review-scope <change>` prints how deep the change's review must
  go: `full`, or `docs-only` when the diff touches nothing outside `docs/` and
  `.plans/`. The loop skips `/code-review` only on `docs-only`, where a code
  reviewer has no code to read. Anything it cannot classify is `full`.
- `worktree.sh land <change>` merges the branch into the primary tree,
  re-runs the suite there, and cleans up. Runs the land gates first.
- `worktree.sh landed <change>` answers "has this change fully landed?" from
  repo artifacts, printing `landed` (exit 0) or `pending` (exit 1). Landed
  means the merge commit is on the primary branch and the branch, worktree,
  and Plan are gone. An orchestrator polls this instead of trusting a
  subagent's report.
- `worktree.sh remove <worktree-path>` removes a worktree hone created, and
  its branch if fully merged.
- `worktree.sh landable` lists worktrees whose branch is ahead of the
  primary branch.
- `worktree.sh grant <change> "who/why"` records your authorization for one
  irreversible change (writes `.hone-grant/<change>`, stamped with your git
  user and the time). *For you, in your own terminal*: the `bash-guard`
  denies it to the agent.
- `worktree.sh attest <change> "what you ran"` records your sign-off that
  the real-environment check ran (writes `.hone-proof/<change>`, stamped with
  the branch tip, your git user, and the time). Also denied to the agent.
  It refuses a description that is empty or only whitespace. It also refuses
  the unedited placeholder from this page: `what you ran`, or `what you ran
  and the outcome`. Case and surrounding quotes make no difference. Both
  refusals exit 2 and write nothing, because a sign-off holding the
  placeholder reads as evidence and carries none.

## Configuration files

*Committed project policy*, shared and versioned and reviewed like any other
file:

- `.hone-durable-paths` lists paths the guard protects beyond the built-in
  `src/ tests/ docs/ db/ scripts/`. One entry per line, `#` comments: a
  directory (`deploy/`) or an exact file (`tsconfig.json`). It can only add
  paths, never remove built-ins.
- `.hone-irreversible-paths` lists path globs that make a change count as
  irreversible, beyond the built-in signals (destructive SQL in a migration
  or `db/` file, a deletion under `db/`). One glob per line, `#` comments.
  The pre-0.19 name `.hone-consequential-paths` still works.
- `.hone-review-always` lists path globs that force `review-scope` to answer
  `full` even when the whole diff sits under `docs/`. One glob per line, `#`
  comments. It exists for prose a project's own tooling *executes*: a prompt, a
  policy file, a template. Without the file, every docs-only diff skips
  `/code-review`.
- `.hone-proof-always` makes the proof gate fire on *every* change, whether or
  not a commit declares the trailer. Its existence is the whole switch, and
  land ignores the contents, so use them for a `#` comment. Commit it, or it
  gates your own lands and nobody else's. With the marker present and no
  `scripts/proof.sh`, land refuses with exit 7 and asks you to add the
  adapter. The guard and the bash-guard protect the marker like the other
  policy files, so removing it stays your call. `worktree.sh status` reports
  the marker and warns while it is uncommitted.

*Per-developer*, gitignored and never checked in:

- `.hone-off` turns off every hook, for a quick manual edit outside the
  loop. Delete it when done. The `bash-guard` refuses to let the agent create
  it.

  Delete the marker only after the commit that cleans the tree. The
  dirty-guard blocks every command while a durable path is dirty. Remove the
  marker before the commit, and the next command blocks. The order is:
  create the marker, edit, run the checks, commit, then delete the marker.
- `.hone-grant/<change>` is your authorization for one irreversible change.
  Its text lands in the merge commit body. Delete the file to revoke. Written
  by `worktree.sh grant`, or by hand (say who, when, and why).
- `.hone-proof/<change>` is your sign-off that the real-environment check for
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

- *guard* (PreToolUse on Write/Edit) enforces three rules. Anywhere, no
  writes into `.hone-grant/` or `.hone-proof/` (sign-offs are the human's)
  and no new file under `src/` unless a test for it exists (test files
  themselves are always writable). In the primary tree, no edits to the
  protected paths at all, including the two policy files; that work belongs
  in a worktree, landed by a merge.
- *bash-guard* (PreToolUse on Bash) provides tamper resistance. It denies
  commands that would disable the gate (`--no-verify`, `core.hooksPath`,
  creating `.hone-off`) or write a grant or proof sign-off (those are the
  human's). It asks before commands that modify a protected artifact (an
  adapter, a hook, settings, a policy file) or move HEAD in the primary tree.
  `git checkout -- <paths>` and `git checkout <ref> -- <paths>` restore files
  and move no HEAD, so both pass.
  It asks before a package manager, a formatter, or a migration tool runs in
  the primary tree. Such a tool writes its own files, so no command text ever
  spells that write out. A bare sync install (`bun install`, `npm ci`, with
  flags only) passes, because it installs what the lockfile already says.
  An install that names a package still asks. It is a deterrent, not a
  sandbox: it closes the obvious shell routes; the settings.json deny rules
  (see *Install* in the README) close the file-tool routes.
- *dirty-guard* (PostToolUse on Bash) reads the effect instead of the command.
  In the primary tree it asks git what the command left dirty, and blocks when
  that list holds a protected path. This catches the writer the bash-guard's name
  list misses, because it never has to recognize the tool. It reports after the
  write, so it stops the run before the commit rather than preventing the edit.
- *gate* (Stop) runs `scripts/run-tests.sh`, plus `scripts/typecheck.sh`
  and `scripts/lint.sh` when they exist, and blocks the turn on any failure.
  With an uncommitted change to any durable path it runs the fast unit tier.
  On a clean `hone/<change>` branch it runs the full suite (the pre-land
  check). A dependency sweep dirties the manifest and the lockfile rather
  than `src/`, and it breaks the suite just as easily, so the gate reads the
  whole durable perimeter and not `src/` and `tests/` alone. The full suite
  runs once per tree. A green run records the tree hash in
  `<git-dir>/hone-gate-green`. A later Stop on that same tree skips the run
  and says so. Any commit, and any plugin upgrade, invalidates the record.
- *nag* (Stop, advisory) reports hygiene findings as a visible message, never
  a block: a Plan that survived its landing, an oversized or orphan Note, a
  broken `Governs:` link, a merged `hone/*` branch left behind, a change
  about to land that deletes nothing, a `type: project` entry in the
  harness's own memory store.
- *session-start* injects the workflow rule from the plugin, and warns
  when the test adapter or the `src/` layout is missing, or when the settings
  lack any rule from the canonical deny list
  (`templates/settings/deny-rules.txt`), naming the missing rules. The
  comparison is semantic: `Edit(./x)` and `Edit(x)` both count, either
  settings file counts, and extra project-specific denies are ignored.

## Land gates

`worktree.sh land` refuses two kinds of change until a human acts. Both
checks run before the merge, so a refused change never touches the trunk, and
the worktree stays for inspection.

- *Authority gate (exit 8)* fires when the diff is irreversible (see
  `.hone-irreversible-paths` above for the signals). Landing it needs your
  grant: review the diff, then `worktree.sh grant <change> "who/why"`, then
  re-run land. The grant text is recorded in the merge commit body. The
  refusal prints the signals that fired and a diffstat against the merge base.
  It also prints the `git diff` command for the whole change, and the grant
  command.
- *Proof gate (exit 7)* fires when a commit on the branch carries a
  `Proof: real-environment — <the check>` trailer (copied verbatim from the
  Plan), meaning no in-repo test can prove the change; a browser journey,
  canary, or deployed check has to. Landing it needs one of: a green run of
  the *primary tree's*
  `scripts/proof.sh` (see *Adapters*: the reviewed copy is executed, so a
  change cannot ship its own green stub), or your sign-off after running the
  check yourself: `worktree.sh attest <change> "what you ran"`. A committed
  `.hone-proof-always` widens this gate to every change (see *Configuration
  files*). A diff that touches the adapter itself arms the gate too, with no
  trailer needed (below).

The proof gate's refusal prints the check the trailer declared, the text
after the dash on the `Proof: real-environment` line. You run that check, so
you should not have to open the Plan to read it. An older trailer carries no
description, and the message stays generic.

One change has no automatic route. Where the diff touches `scripts/proof.sh`
or anything under `scripts/proof-probes/`, land cannot prove it. The copy land
holds is the one the change replaces. The refusal then
tells you to run `bash scripts/proof.sh <change>` from the worktree in your
own terminal, and to attest with its output.

That same diff also *arms* the gate on its own. A change touching the adapter
or a probe needs no trailer and no marker to reach exit 7. The adapter defines
the verdict this gate trusts, so a change to it always reaches you. The loop
may still write that change in its worktree, which is why the gate carries the
weight instead of a ban on writing.

The agent never writes a grant or sign-off and never runs the helpers: the
guard denies the file-tool routes and the bash-guard the shell routes (a
deterrent, not a sandbox). When a gate fires during an unattended run, the
run stops and reports; that is the intended behavior, not a failure. The
gate's error message prints the exact helper command with its full path.

## Exit codes

`worktree.sh land`:

| Exit | Meaning |
|------|---------|
| 0 | landed and green |
| 2 | usage or repo-state error (missing branch, detached HEAD) |
| 5 | lock timeout: another land or full-suite run held the lock |
| 6 | suite, type-check, or lint red after the merge; rolled back, worktree kept, output in the land log |
| 7 | proof gate: real-environment proof missing |
| 8 | authority gate: irreversible change without a grant |
| 9 | merge conflict; aborted, tree restored, branch kept |

What to do at each code, in detail:
[`skills/run/references/land.md`](../skills/run/references/land.md).

After a green suite, land also runs `scripts/typecheck.sh` and
`scripts/lint.sh` where they exist, the same optional adapters the gate runs.
The merge result is a tree no gate has checked: two changes that each append
to one file can be lint-green alone and lint-red merged. A red adapter rolls
the merge back with the same exit 6, and the message names the adapter.

The post-merge suite writes `<git-common-dir>/hone-land.log`, replaced on
every land, and the adapter runs append to it. Exit 6 prints that path and
the last 20 lines of it.

After a green post-merge run, land reads the tier summary lines out of that
log. It then warns about every tier that reported `ran=0`, because a tier
that matched no test makes the green prove nothing. The warning never blocks:
land exits 0 and the merge stands. An adapter that prints no summary lines
draws no warning.

Other subcommands: `add` exits 4 when the change is already claimed by
another run (0 created, 2 error); `remove` exits 3 when the path is not one
hone created (0 removed, 2 error); `verify` passes through the adapter's exit
(2 setup error, 5 lock timeout). `landed` exits 1 while the change is
pending (0 landed, 2 error).

## Adapters

One script per job, all under the project's `scripts/`; the gate and the loop
call them so hone itself stays language-agnostic.

- `run-tests.sh` is required. Unit tier by default, `--all` for every tier,
  `<files...>` for specific files. Under `--all` it should also print one
  summary line per tier it ran, `hone tier: <name> ran=<count>`, taking the
  count from the runner's own total. An adapter that cannot read that total
  prints no line. Contract and per-ecosystem
  templates: [`templates/run-tests/README.md`](../templates/run-tests/README.md).
  Installed by `setup.sh`.
- `typecheck.sh` and `lint.sh` are optional, one line each, run by the gate
  and by land's post-merge check when present.
- `proof.sh` is optional; it proves a change in the real environment for the
  proof gate. land executes the primary tree's copy, with the change's
  worktree as the working directory, so a change adding its own `proof.sh`
  is only trusted after that adapter has landed. Invoked as
  `proof.sh <change>`. Contract and templates:
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
├── .hone-proof-always           # committed policy (optional): prove every change
└── .claude/settings.json        # enables the plugin; deny rules for the adapters
```

The plugin itself:

```
hone/
├── rules/workflow.md            # injected at session start
├── skills/{setup,plan,run,garden}/ # the four commands; run/references/ loads on demand
├── hooks/                       # guard, bash-guard, dirty-guard, gate, nag, session-start
│   └── messages.sh              # every message hone prints, one template each
├── scripts/{worktree,setup}.sh
├── agents/                      # plan-critic, consolidate-critic
├── templates/{run-tests,proof}/ # adapter contracts and templates
├── templates/settings/          # the canonical deny-rules list
└── evals/                       # known-good answers for the critics and the loop
```

## What writes what

W = writes, M = amends, P = prunes/deletes, R = reads, . = untouched

| Operation   | .plans/ | code | tests | decisions/ | notes/ | open-q | .git |
|-------------|---------|------|-------|------------|--------|--------|------|
| plan        | W       | R    | R     | R          | R      | (W)    | W    |
| build       | R/P     | W    | W     | .          | .      | .      | .    |
| verify      | .       | R    | R     | R          | R      | R      | .    |
| consolidate | P       | .    | P     | W/M        | W/M    | M      | .    |
| land        | .       | .    | .     | .          | .      | .      | W    |
| garden      | P       | P    | P     | P          | P      | P      | W    |

Notes on the rarer cells: plan's reads are its step 2, where it reads the code,
the tests, and the area's Decisions and Notes. The Plan can then state what the
change replaces. plan's `(W)` on open questions covers only a new
question the Plan surfaces, and its `.git` write is the commit of the Plan
and its references on the trunk. build's `.plans/` prune is a reference
promoted out (`git mv`'d next to the test that reads it; build is the only
step that writes tests). consolidate's `.plans/` prune is the `git rm` of the
Plan and any references build did not promote. garden is not part of a
change: it is the standalone maintenance loop, and every column it touches is
a deletion.
