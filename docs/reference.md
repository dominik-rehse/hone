# Reference

The complete control surface: commands, configuration files, hooks, land
gates, exit codes, adapters, and layout. Everything else links here. When a
detail on this page and prose elsewhere disagree, this page wins.
[`model.md`](model.md) explains why the pieces exist.

## Commands

Slash commands, in the order a change flows:

- `/hone:setup` runs once per project: `scripts/setup.sh` for the mechanics,
  then a verification of the install. The verification authors the adapter
  where detection fell short, executes every installed adapter, fixes what
  fails, and completes the settings block. It is interactive, so run it with
  the human present.
- `/hone:plan <change>` writes and commits the Plan for one change. The
  `plan-critic` checks the Plan while its caller is present. This is the one
  step outside the loop. A human usually invokes it, and another agent may
  invoke it too, as it may invoke `/hone:run`.
- `/hone:run <change>` executes the Plan unattended (worktree, build, verify,
  consolidate, review, land). `/hone:run --all` runs every ready Plan.
- Inside [herdr](https://github.com/dominik-rehse/herdr), which `run` detects on
  its own, `--all` spreads those Plans over herdr tabs. This tab
  becomes `MAIN:<short>` and orchestrates. Each Plan gets a fresh Claude Code
  session in its own `SUB` tab (`--model` picks their model). MAIN starts a
  dependent Plan only when `worktree.sh landed` shows the predecessor landed, and
  closes a SUB tab only then. Probes, proofs, and everything else plan-specific
  happen in the SUB tab, never in MAIN. For a workspace of their own, create the
  workspace and invoke the command in it.
- `/hone:garden` scans the repo for stale docs, dead code, and redundant tests
  between changes, and lands the safe deletions. You invoke it, as often as
  the repo needs it.

`worktree.sh` (in the plugin's `scripts/` directory) does the mechanical git
work. The loop calls it, and you can too:

- `worktree.sh status` shows the state of everything on this page in one
  screen. That covers hooks, adapters, policy files and their commit state,
  pending Plans, worktrees in flight, grants and sign-offs, and the settings
  deny rules.
- `worktree.sh add <change>` creates `.worktrees/<change>` on branch
  `hone/<change>`. Creating it is what claims the change, so a second `add`
  of the same name fails.
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
  the marker and warns until you commit it.

*Per-developer*, gitignored and never checked in:

- `.hone-off` turns off every hook, for a quick manual edit outside the
  loop. Delete it when done. The `bash-guard` refuses to let the agent create
  it.

  Delete the marker only after the commit that cleans the tree. The
  dirty-guard blocks every command while a durable path is dirty. Remove the
  marker before the commit, and the next command blocks. The order is:
  create the marker, edit, run the checks, commit, then delete the marker.
- `.hone-grant/<change>` is the authorization for one irreversible change.
  Its text lands in the merge commit body. Delete the file to revoke. Write it
  with `worktree.sh grant` (say who, when, and why), yourself or through the
  loop. By hand in your own editor works too, and the guards deny the loop
  that route.
- `.hone-proof/<change>` is the sign-off that the real-environment check for
  one change ran. It must contain the commit hash it applies to (short or
  full). After new commits it no longer counts. Same two writers and the
  same rule: `worktree.sh attest`, or your own editor.

Two environment variables tune the cross-session locks.
`HONE_LAND_LOCK_TIMEOUT` sets the seconds a land or full-suite run waits for
the lock (default 600). `HONE_SUITE_LOCK_TIMEOUT` sets the seconds the
gate's pre-land full run waits (default 30).

## Hooks

`.hone-off` disables all of them at once. A project with no
`scripts/run-tests.sh` is never gated, and enforcement assumes code lives
under `src/<area>/`.

- *guard* (PreToolUse on Write/Edit) enforces three rules. Anywhere, no
  writes into `.hone-grant/` or `.hone-proof/` (the helpers write those).
  Anywhere, no new file under `src/` unless a test for it exists (test files
  themselves stay writable). In the primary tree, no edits to the protected
  paths at all, including the two policy files. That work belongs in a
  worktree, landed by a merge.
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
  sandbox. It closes the obvious shell routes, and the settings.json deny
  rules (see *Install* in the README) close the file-tool routes.
- *dirty-guard* (PostToolUse on Bash) reads the effect instead of the command.
  In the primary tree it asks git what the command left dirty, and blocks when
  that list holds a protected path. This catches the writer the bash-guard's name
  list misses, because it never has to recognize the tool. It reports after the
  write, so it stops the run before the commit rather than preventing the edit.
- *gate* (Stop) runs `scripts/run-tests.sh`, plus `scripts/typecheck.sh`
  and `scripts/lint.sh` when they exist, and blocks the turn on any failure.
  With an uncommitted change to any durable path it runs the fast unit tier.
  On a clean `hone/<change>` branch it runs the full suite (the pre-land
  check). A dependency refresh dirties the manifest and the lockfile rather
  than `src/`, and it breaks the suite just as easily. So the gate reads the
  whole durable perimeter, not `src/` and `tests/` alone. The full suite
  runs once per tree. A green run records the tree hash in
  `<git-dir>/hone-gate-green`. A later Stop on that same tree skips the run
  and says so. Any commit, and any plugin upgrade, invalidates the record.
- *nag* (Stop, advisory) reports hygiene findings as a visible message,
  never a block. The findings:
  - a Plan that survived its landing
  - an oversized or orphan Note
  - a broken `Governs:` link
  - a merged `hone/*` branch left behind
  - a change about to land that deletes nothing
  - a `type: project` entry in the harness's own memory store
- *session-start* injects the workflow rule from the plugin. It warns when
  the test adapter or the `src/` layout is missing. It also warns, naming
  the missing rules, when the settings lack any rule from the canonical deny
  list (`templates/settings/deny-rules.txt`). The comparison is semantic:
  `Edit(./x)` and `Edit(x)` both count, either settings file counts, and
  the warning ignores extra project-specific denies.

## Land gates

`worktree.sh land` refuses two kinds of change until a grant or a proof
exists. Both checks run before the merge, so a refused change never touches
the primary tree, and the worktree stays for inspection.

- *Authority gate (exit 8)* fires when the diff is irreversible (see
  `.hone-irreversible-paths` above for the signals). Landing it needs your
  grant: review the diff, then `worktree.sh grant <change> "who/why"`, then
  re-run land. land records the grant text in the merge commit body. The
  refusal prints the signals that fired and a diffstat against the merge base.
  It also prints the `git diff` command for the whole change, and the grant
  command.
- *Proof gate (exit 7)* fires when a commit on the branch carries a
  `Proof: real-environment — <the check>` trailer (copied verbatim from the
  Plan). The trailer means no in-repo test can prove the change: a browser
  journey, a canary, or a deployed check has to. Landing it needs one of two
  things. The first is a green run of the *primary tree's*
  `scripts/proof.sh`. land executes the reviewed copy (see *Adapters*), so a
  change cannot ship its own green stub. The second is your sign-off after
  you ran the check yourself:
  `worktree.sh attest <change> "what you ran"`. A committed
  `.hone-proof-always` widens this gate to every change (see *Configuration
  files*). A diff that touches the adapter itself arms the gate too, with no
  trailer needed (below).

The proof gate's refusal prints the check the trailer declared, the text
after the dash on the `Proof: real-environment` line. You run that check, so
you should not have to open the Plan to read it. An older trailer carries no
description, and the message stays generic.

One change has no automatic route. Where the diff rewrites the proof harness,
land cannot prove it, because the copy land holds is the one the change
replaces. Two diffs count as rewriting it: any change to `scripts/proof.sh`,
and a change to a probe under `scripts/proof-probes/` that already exists. The
refusal then tells you to run `bash scripts/proof.sh <change>` from the
worktree in your own terminal, and to attest with its output.

That same diff also *arms* the gate on its own. Such a change needs no trailer
and no marker to reach exit 7. The adapter defines the verdict this gate
trusts, so a change to it always reaches you. The loop may still write that
change in its worktree, which is why the gate carries the weight instead of a
ban on writing.

A change that only *adds* a new probe is outside this. It writes its own check,
the way it writes its own tests, and the adapter that judges it stays the
reviewed copy. Without this exception the gate fired on every proof-carrying
change in a project whose adapter asks each change for its own probe. That is
the shape [`templates/proof/README.md`](../templates/proof/README.md)
recommends. An edit to a probe that already exists still arms the gate: that
probe guards a change that landed earlier.

Both you and the loop record a grant or a sign-off, and both do it with
`worktree.sh grant` and `worktree.sh attest`. Every other route stays denied:
the guard blocks the file-tool routes into `.hone-grant/` and `.hone-proof/`,
and the bash-guard the shell routes (a deterrent, not a sandbox). The helper
is what stamps the signer, binds a sign-off to the commit it proves, and
refuses an empty or placeholder text.

The stamp separates the two. A record the loop writes opens with
`agent, on behalf of`, keyed off `CLAUDECODE` in the environment, so a later
audit can tell an agent grant from yours. It is a label for a reader, not a
lock.

An unattended run discharges its own gates. On exit 8 it reads the diff the
refusal printed and records why the irreversible change is right. On exit 7 it
runs the check the refusal names and records what that run printed. It stops
and reports instead in two cases. Either the check is out of its reach (a
browser journey with no adapter), or the diff does something the Plan never
asked for.
The gate's error message prints the exact helper command with its full path.

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

Other subcommands:

- `add` exits 4 when another run has already claimed the change (0 created,
  2 error).
- `remove` exits 3 when the path is not one hone created (0 removed,
  2 error).
- `verify` passes through the adapter's exit (2 setup error, 5 lock
  timeout).
- `landed` exits 1 while the change is pending (0 landed, 2 error).

## Adapters

One script per job, all under the project's `scripts/`. The gate and the
loop call them, so hone itself stays language-agnostic.

- `run-tests.sh` is the one required adapter. Unit tier by default, `--all`
  for every tier, `<files...>` for specific files. Under `--all` it should
  also print one summary line per tier it ran, `hone tier: <name>
  ran=<count>`, taking the count from the runner's own total. An adapter
  that cannot read that total prints no line. Contract and per-ecosystem
  templates: [`templates/run-tests/README.md`](../templates/run-tests/README.md).
  `setup.sh` installs it.
- `typecheck.sh` and `lint.sh` are optional, one line each. The gate and
  land's post-merge check run them when they exist.
- `proof.sh` is optional. It proves a change in the real environment for the
  proof gate. land executes the primary tree's copy, with the change's
  worktree as the working directory. So land trusts a change that adds its
  own `proof.sh` only after that adapter has landed. land invokes it as
  `proof.sh <change>`. Contract and templates:
  [`templates/proof/README.md`](../templates/proof/README.md).

## Project layout

```
repo/                            # the primary tree: a merge target, never a workspace
├── src/<area>/                  # code + tests (thing.ts / thing.test.ts, thing.py / test_thing.py)
├── docs/
│   ├── decisions/<topic>.md     # one present-tense decision + why, per topic
│   ├── notes/<area>.md          # optional per-area map + one invariant, size-capped
│   ├── spikes/<date>-<slug>*    # optional frozen spike: note, probe, captures, any type
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
├── templates/spike-note.md      # the shape of a frozen spike note
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
question the Plan surfaces. Its `.git` write is the commit of the Plan
and its references on the primary branch. build's `.plans/` prune is a
reference promoted out, `git mv`'d next to the test that reads it. (build
is the only step that writes tests.) consolidate's `.plans/` prune is the `git rm` of the
Plan and any references build did not promote. garden is not part of a
change: it is the standalone maintenance loop, and every column it touches is
a deletion.

Spikes are outside the table, because a spike is not a change. Everything one
spike leaves behind lives under `docs/spikes/`, whatever its type. Examples:
the note, the probe code that produced it, a mockup, a captured payload, a
screenshot.
One spike is one dated stem, `<YYYY-MM-DD>-<slug>`, a single file where one
file is enough and a directory where it is not. No hook looks inside, so a
probe needs no test and no worktree, and nothing there has to keep the suite
green by itself.

Both `plan` (before a Plan exists) and `consolidate` (after the change) write a
spike. `docs/spikes/` is the one path under `docs/` the guard leaves
writable in the primary tree, exactly as it leaves `.plans/`. Most probes leave
nothing behind: keep a spike only when its method or its dead ends would save a
future reader from running it again.

The note at `<YYYY-MM-DD>-<slug>.md` is the way in. It is write-once, past
tense, and it always points forward to the Decision, Note, or open question
that carries the finding. The date is what says so: the `nag` reports any entry
under `docs/spikes/` without one, `garden` never cuts a spike for being old,
and nobody updates one. A note that starts describing what the system does
today has become a second spec, and the `consolidate-critic` argues for that
cut. `garden` cuts a spike whole, stem and all, because the stem is the unit.
Copy the shape from [`templates/spike-note.md`](../templates/spike-note.md).

Committed probe code has one practical cost. A project's test runner, linter,
or type-checker may pick up a file under `docs/spikes/`, and the gate needs all
three green. Exclude the directory in those adapters the first time a spike
trips one.
