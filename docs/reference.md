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
  `plan-critic` checks the Plan against the caller's sketch while that caller
  is present. This is the one
  step outside the loop. A human usually invokes it, and another agent may
  invoke it too, as it may invoke `/hone:run`.
- `/hone:run <change>` executes the Plan unattended (worktree, build, verify,
  consolidate, review, land). `/hone:run --all` runs every ready Plan.
- Inside [herdr](https://github.com/dominik-rehse/herdr), which `run` detects on
  its own, `--all` spreads those Plans over herdr tabs. This tab
  becomes `MAIN:<short>` and orchestrates. Each Plan gets a fresh Claude Code
  session in its own `SUB` tab. Those sessions run on `opus`, and `--model`
  picks another model where you want one. MAIN starts a
  dependent Plan only when `worktree.sh landed` shows the predecessor landed, and
  closes a SUB tab only then. Probes, proofs, and everything else plan-specific
  happen in the SUB tab, never in MAIN. For a workspace of their own, create the
  workspace and invoke the command in it.
- `/hone:garden` scans the repo for stale docs, dead code, and redundant tests
  between changes, and lands the safe deletions. It also repoints a `docs/`
  reference whose target moved, and escalates the rest as one proposed Plan per
  area. You invoke it, as often as the repo needs it, and another agent may
  invoke it too.

Two steps run on the `opus` alias, not on a model version. The critics run on
the `model:` of their frontmatter in `agents/`, and the nested
`/code-review` runs on the `--model` of the command in the run skill. The
alias follows the newest Opus that your Claude Code maps it to. So a new Opus
reaches these steps when Claude Code updates, with no hone release. The review command
also names its level, `high`, in the prompt. Without a level there,
`/code-review` reuses the level you typed last. The session itself
runs on whatever model you chose. Claude Code reads the frontmatter before
`CLAUDE_CODE_SUBAGENT_MODEL`, so that variable moves a critic only together
with `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`. On a provider that names its
models differently, set the model that the alias maps to with
`ANTHROPIC_DEFAULT_OPUS_MODEL`. hone's evals do not cover such a setup.

`worktree.sh` (in the plugin's `scripts/` directory) does the mechanical git
work. The loop calls it, and you can too:

- `worktree.sh status` shows the state of everything on this page in one
  screen. That covers hooks, adapters, policy files and their commit state,
  pending Plans, worktrees in flight, grants and sign-offs, and the settings
  deny rules.
- `worktree.sh add <change>` creates `.worktrees/<change>` on branch
  `hone/<change>`. Creating it is what claims the change, so a second `add`
  of the same name fails. In shared mode (see *Configuration files*) the
  claim lives on the remote, so a second `add` from any clone fails. When
  the project ships `scripts/setup-tree.sh`, `add` then runs it inside the
  new worktree (see *Adapters*).
- `worktree.sh verify` runs the full test suite, serialized against other
  sessions. The only sanctioned way to run `--all` by hand.
- `worktree.sh review-scope <change>` prints how deep the change's review must
  go: `full`, or `docs-only` when the diff touches nothing outside `docs/` and
  `.plans/`. The loop skips `/code-review` only on `docs-only`, where a code
  reviewer has no code to read. Anything it cannot classify is `full`.
- `worktree.sh governed <change>` prints the Decisions and Notes about the
  code that the change touched, one path per line. A document counts when
  a path on its `Governs:` line is a changed file or a directory above one.
  A path may be a glob, and it expands in the change's tree. A Note also
  counts by its name, because `docs/notes/<area>.md` is about
  `src/<area>/`. With no worktree left, the command reads the primary
  tree's documents. The loop hands these documents to the `consolidate-critic`,
  whether the change opened them or not.
- `worktree.sh land <change>` builds the merge in the change's worktree,
  re-runs the suite there, fast-forwards the primary branch onto the tested
  merge commit, and cleans up. Runs the land gates first. When the primary
  branch moved during the suite, it merges and verifies again. A missing
  worktree is cut again from the branch. In shared
  mode it merges on top of the remote's latest and pushes the tested result
  (see *Shared mode* under *Land gates*).
- `worktree.sh landed <change>` answers "has this change fully landed?" from
  repo artifacts, printing `landed` (exit 0) or `pending` (exit 1). Landed
  means the merge commit is on the primary branch and the branch, worktree,
  and Plan are gone. An orchestrator polls this instead of trusting a
  subagent's report. In shared mode it reads the remote primary branch, so
  the answer holds from any clone.
- `worktree.sh sync` levels the primary tree with the remote primary branch
  in both directions: fetch, fast-forward or rebase local-only commits on
  top, then push them. Shared mode only. The plan skill runs it after
  committing a Plan, `run --all` and `garden` run it before reading the
  queue, and you run it to catch up.
- `worktree.sh release <change>` deletes a claim from the remote by hand,
  for a change whose worktree is already gone. `remove` does it with the
  worktree.
- `worktree.sh remove <worktree-path | change>` removes a worktree hone
  created, and its branch if fully merged.
- `worktree.sh landable` lists worktrees whose branch is ahead of the
  primary branch.
- `worktree.sh grant <change> "who/why"` records the authorization for one
  irreversible change (writes `.hone-grant/<change>`, stamped with the git
  user and the time). A person and the agent both run it, and the stamp says
  which. It is the only route to the file: both guards deny a raw write.
  It refuses a text that is empty or only whitespace, and the `who/why`
  placeholder from this page, exact or half-edited (`rehse/why`). Case and
  surrounding quotes make no difference. The refusals exit 2 and write
  nothing, because a placeholder authorizes nothing a reader can check.
- `worktree.sh attest <change> "what you ran"` records the sign-off that
  the real-environment check ran (writes `.hone-proof/<change>`, stamped with
  the branch tip, the git user, and the time). You run it, and only you: the
  `bash-guard` denies it to the loop, which runs the check where it can and
  hands you the output. Same sole-route rule as grant.
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

- `.hone-shared` turns on *shared mode*: the primary branch belongs to a
  team, on a remote. Its first non-comment line names the remote, and a
  blank file means `origin`. With the marker committed, `add` claims a
  change on the remote, and `land` merges on top of the remote's latest and
  pushes the tested result. `landed` and `sync` read the remote. Without
  it, hone never pushes, so a solo repository with a backup remote keeps
  working as before. The remote must accept pushes to `refs/hone/*`, which
  GitHub, GitLab, and Gitea do. `worktree.sh status` reports the marker,
  warns until you commit it, and lists the claims other developers hold.
  The guard and the bash-guard protect the marker like the other policy
  files, so turning shared mode off stays your call.

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
  that route. A green land deletes the spent file. A grant is not pinned to
  a commit, so a leftover one would authorize a later change that reuses the
  slug.
- `.hone-proof/<change>` is the sign-off that the real-environment check for
  one change ran. It must contain the commit hash it applies to (short or
  full). After new commits it no longer counts. You write it, with
  `worktree.sh attest` or your own editor, and the loop never does. A
  sign-off that opened
  the proof gate lands in the merge commit body like a grant, and a green
  land deletes the spent file.

Three environment variables tune the cross-session mechanics.
`HONE_LAND_LOCK_TIMEOUT` sets the seconds a land or full-suite run waits for
the lock (default 600). `HONE_SUITE_LOCK_TIMEOUT` sets the seconds the
gate's pre-land full run waits (default 30). `HONE_LAND_RETRIES` sets how
many times land redoes merge and suite after the primary branch moved, or
the remote rejected its push (default 3).

Two more variables tune a hook. `HONE_AREA_MAX_LINES` sets the size above
which the nag names a `src/<area>/` (default 3000). `HONE_GATE_BLOCK_CAP`
sets how many identical failures the gate blocks a turn end for before it
lets the turn end (default 3).

## Hooks

`.hone-off` disables all of them at once. A project with no
`scripts/run-tests.sh` is never gated, and enforcement assumes code lives
under `src/<area>/`.

The hooks run inside the agent's session, and nowhere else. An edit you make
in your own editor or terminal never meets them. That is the intended
division: the perimeter binds the agent, not you. The cost is on the record.
hone writes a grant and a sign-off only for a change that lands through the
loop. A hand edit leaves neither, even on a path the policy files mark
irreversible. When you want that record, route the edit through the loop.

- *guard* (PreToolUse on Write/Edit) enforces three rules and asks in one
  case:
  - Anywhere, no writes into `.hone-grant/` or `.hone-proof/`. The helpers
    write those.
  - Anywhere, no new file under `src/` unless a test for it exists. Test
    files themselves stay writable.
  - In the primary tree, no edits to the protected paths at all, including
    the two policy files. That work belongs in a worktree, landed by a
    merge.
  - In any tree, it asks before an edit to a check config. The gate's runs
    are only as strict as their config, so an edit there is the cheapest
    route from red to green.

  A check config is the dedicated config file of one of three tools:
  - a test runner (`bunfig.toml`, `vitest.config.*`, `jest.config.*`,
    `pytest.ini`)
  - a linter or formatter (eslint, prettier, biome, dprint, ruff,
    shellcheck)
  - a type-checker (`tsconfig*.json`, mypy, pyright)

  A manifest that also carries tool settings (`package.json`,
  `pyproject.toml`) is not in the set. `HONE_CHECK_CONFIG_RE` in
  `hooks/common.sh` is the full list.
- *bash-guard* (PreToolUse on Bash) provides tamper resistance. It is a
  deterrent, not a sandbox. It closes the obvious shell routes, and the
  settings.json deny rules (see *Install* in the README) close the
  file-tool routes.
  - It denies a command that would disable the gate: `--no-verify`,
    `core.hooksPath` in any case, or creating `.hone-off`.
  - It denies a command that hand-writes a grant or a proof sign-off past
    the `worktree.sh` helpers.
  - It asks before a command that modifies a protected artifact: an
    adapter, a hook, settings, a policy file, or a check config. The ask
    names the file. A check config outside the repository passes.
  - It asks before a command that moves HEAD in the primary tree.
    `git checkout -- <paths>` and `git checkout <ref> -- <paths>` restore
    files and move no HEAD, so both pass.
  - It asks before a command that moves the primary branch itself there.
    The list is `git merge`, `cherry-pick`, `rebase`, `branch -f`, and
    `update-ref` on `refs/heads/`. A push whose remote is a local path
    counts, and so does every `git reset` that does more than unstage.
    `worktree.sh land` is the route, and it passes. `git merge-base` and
    `git log --merges` read history, so they pass too. A push of the
    change branch to the team's remote passes.
  - It asks before a package manager, a formatter, or a migration tool
    runs in the primary tree. Such a tool writes its own files, so no
    command text ever spells that write out. A bare sync install
    (`bun install`, `npm ci`, with flags only) passes, because it installs
    what the lockfile already says. An install that names a package still
    asks.

  It reads the command with its prose removed: the value of a git `-m` or
  `--message` option, and the text after `worktree.sh grant` or `attest`.
  So a commit message that names `--no-verify` or `bun add` is not the act.

  Every primary-tree rule judges each simple command in the tree it runs
  in. It starts from the *shell's* directory, which the harness reports, and
  follows `cd`, subshells, `git -C`, and a variable set to a literal path or
  `$(mktemp -d)`. A tree it cannot resolve counts as the primary tree.
- *dirty-guard* (PostToolUse on Bash) reads the effect instead of the command.
  In the primary tree it asks git what the command left dirty, and blocks when
  that list holds a protected path. It catches a writer the bash-guard's name
  list misses. It reports after the
  write, so it stops the run before the commit. During a merge, cherry-pick,
  revert, or rebase, it skips that operation's staged and conflicted paths.
- *gate* (Stop) runs `scripts/run-tests.sh`, plus `scripts/typecheck.sh`
  and `scripts/lint.sh` when they exist, and blocks the turn on any failure.
  - With an uncommitted change to any durable path it runs the fast unit
    tier. A dependency refresh dirties the manifest and the lockfile rather
    than `src/`, and it breaks the suite just as easily. So the gate reads
    the whole durable perimeter, not `src/` and `tests/` alone.
  - On a clean `hone/<change>` branch it runs the full suite, once per
    change branch. This is the pre-land check. A green run records the
    branch and the tree it verified in `<git-dir>/hone-gate-green`. Every
    later Stop on that branch skips the run and says so, and a plugin
    upgrade invalidates the record. When a land or a verify holds the land
    lock, often this session's own, the gate blocks under the cap below.

  - A Stop hook runs where the agent's shell stands, and the agent moves it.
    So when this session was already blocked in a linked worktree of the
    repository, the gate evaluates that worktree, wherever the shell stands.
    It reads the counter below to find it. A session that was never blocked,
    and a shell whose own tree has work in flight, see no such redirect.
  - It blocks the same failure `HONE_GATE_BLOCK_CAP` times at most (default
    3). Two failures are the same when the step, the exit code, and the
    output match, with every run of digits collapsed. The last of those
    blocks asks the run for its final report in that turn. The next stop on
    the same failure does not block, and the gate prints one line for you.
    So the turn the person reads holds a report. The count lives in
    `<git-dir>/hone-gate-blocks`, per session. A green run deletes it, and a
    different failure starts it over.

  `land` re-runs the full suite after the merge, so it still catches a
  regression that a later commit introduces. The cap is the turn's and
  never the trunk's: a red change still cannot land.
- *nag* (Stop, advisory) reports hygiene findings as a visible message,
  never a block. The findings:
  - a Plan that survived its landing
  - an oversized or orphan Note
  - a broken `Governs:` link
  - a relative markdown link in a Decision or Note that does not resolve,
    outside code
  - a merged `hone/*` branch left behind
  - a claim this clone holds on the remote with no worktree (shared mode)
  - a change about to land that deletes nothing
  - a `src/<area>/` that a change about to land touched, with more lines
    in its tracked text files than `HONE_AREA_MAX_LINES` (default 3000)
  - a `type: project` entry in the harness's own memory store

  It prints the full list once per session and tree, and again when it
  changes. Otherwise it prints the count.
- *session-start* injects the workflow rule from the plugin. It warns when
  the test adapter or the `src/` layout is missing. It also warns, naming
  the missing rules, when the settings lack any rule from the canonical deny
  list (`templates/settings/deny-rules.txt`). The comparison is semantic:
  `Edit(./x)` and `Edit(x)` both count, either settings file counts, and
  the warning ignores extra project-specific denies.

## Land gates

`worktree.sh land` runs three checks before the merge. The first reads the
shape of the change. The other two refuse a kind of change until a grant
or a proof exists. A refused change never touches the primary tree, and
the worktree stays for inspection.

For the shape check, some commit on the branch must carry a body line `Cut:
<what the change removed>`, or `Cut: nothing` with the reason. A garden repair
carries `Repair: <what>` instead. A line that is a placeholder in angle
brackets, or a bare `Cut: nothing` with no reason, records nothing and does not
count. A branch with no such line is exit 2, and the fix is to amend the commit
in the worktree. This check comes first because an amended commit moves the tip,
and a proof sign-off names the tip.

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

Both you and the loop record a grant, with `worktree.sh grant`. Only you
record a sign-off, with `worktree.sh attest`. The `bash-guard` denies the loop
that helper. The loop runs the check where it can, hands you the output, and
stops. Every other route stays denied:
the guard blocks the file-tool routes into `.hone-grant/` and `.hone-proof/`,
and the bash-guard the shell routes (a deterrent, not a sandbox). The helper
is what stamps the signer, binds a sign-off to the commit it proves, and
refuses an empty or placeholder text.

### Shared mode

With `.hone-shared` committed, land is the team's merge queue, and git is
the lock. Under its own land lock, land first levels the primary tree with
the remote: it fetches, then fast-forwards, or rebases local-only commits on
top. A rebase that conflicts aborts and refuses. Then it merges the branch,
runs the suite, and pushes the primary branch. Git rejects the push when
another developer landed while the suite ran, because the merge is no
longer a straight extension of the remote. land then undoes its local
fast-forward, levels again, and redoes merge and suite. It gives up after
`HONE_LAND_RETRIES` attempts with exit 5, nothing published and the
worktree kept. So a commit never reaches the remote unless the suite passed
on exactly that tree, and merges from several machines serialize on the
suite's duration.

The claim is a ref on the remote, `refs/hone/claim/<change>`, pointing at a
detached commit that names who claimed, on which host, and when. The commit
sits on no branch, so it never enters history. `add` pushes it with a lease
that says the ref must not exist yet, so of two developers racing on one
change exactly one wins. A green land deletes it. A land that stops keeps
it, like the worktree. You release a claim whose owner walked away by hand:

```
git push origin --delete refs/hone/claim/<change>
```

`worktree.sh status` lists the claims other developers hold. `worktree.sh
remove` releases the claim with the worktree, and `worktree.sh release
<change>` releases one whose worktree is already gone. The nag reports a
claim this clone still holds with no worktree.

Shared mode pushes straight to the primary branch. A host that protects that
branch refuses the push. land then exits 2 with the host's reason, undoes its
local fast-forward, and keeps the worktree. It does not retry, and it does not open a
pull request. Either allow direct pushes for the developers who land, or
leave shared mode off.

The stamp separates the two. A record the loop writes opens with
`agent, on behalf of`, keyed off `CLAUDECODE` in the environment, so a later
audit can tell an agent grant from yours. It is a label for a reader, not a
lock.

An unattended run discharges its own gates. On exit 8 it reads the refusal's quoted
statements and diff, and records why the irreversible change is right. On exit 7 it
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
| 2 | usage or repo-state error (missing branch, detached HEAD, no `Cut:` line on the branch, land run from inside the worktree, uncommitted changes in the worktree, a merge git refused to start, files in the primary tree that stopped the fast-forward), or in shared mode a push the host refused |
| 5 | lock timeout: another land or full-suite run held the lock. Also: the primary branch, or in shared mode the remote, moved on every attempt; nothing published |
| 6 | suite, type-check, lint, or setup-tree red on the merge, or a git hook refused the merge commit; primary branch unmoved, worktree kept, output in the land log |
| 7 | proof gate: real-environment proof missing |
| 8 | authority gate: irreversible change without a grant |
| 9 | merge conflict; aborted, tree restored, branch kept, conflicting paths named |

What to do at each code, in detail:
[`skills/run/references/land.md`](../skills/run/references/land.md).

After a green suite, land also runs `scripts/typecheck.sh` and
`scripts/lint.sh` where they exist, the same optional adapters the gate runs.
The merge result is a tree no gate has checked: two changes that each append
to one file can be lint-green alone and lint-red merged. A red adapter fails
the land with the same exit 6, and the message names the adapter.

The merge and its suite write `<git-common-dir>/hone-land.log`,
replaced on every land, and the adapter runs append to it. Exit 6 prints that path and
the last 20 lines of it.

After a green run on the merge, land reads the tier summary lines out of that
log. It then warns about every tier that reported `ran=0`, because a tier
that matched no test makes the green prove nothing. The warning never blocks:
land exits 0 and the merge stands. An adapter that prints no summary lines
draws no warning.

Other subcommands:

- `add` exits 4 when another run has already claimed the change (0 created, 2
  error). The refusal says what the claim holds, and it names one action. A file
  in the worktree that changed in the last 30 minutes means a run at work, and
  the action is to wait. An older worktree with commits or uncommitted files is
  work for a person to read. An older worktree with neither is safe to remove,
  and the refusal prints the `remove` command. In shared mode that run may be on
  another machine, and a refused claim leaves nothing local behind. A failed
  `setup-tree.sh` run is exit 2 with the worktree kept: the claim stands, and
  the message carries the adapter's output tail.
- `remove` exits 3 when the path is not one hone created (0 removed,
  2 error).
- `verify` passes through the adapter's exit (2 setup error, 5 lock
  timeout).
- `landed` exits 1 while the change is pending (0 landed, 2 error).
- `sync` exits 0 when the primary tree is level with the remote, and 5
  when the remote moved on every push attempt. It exits 2 on a setup or
  state problem. Those are: not shared, no such remote, a dirty primary
  tree, a failed fetch, a rebase conflict, and a push the host refused.
- `release` exits 0 when the claim is gone (2 not shared, no such remote,
  or the delete failed).

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
  land's check of the merge run them when they exist. They are also where a
  project enforces code quality with a tool of its choice. The goals are no
  copied code, no dead code, small functions, boundaries between areas, and
  strict types.
  [`templates/quality/README.md`](../templates/quality/README.md) maps each
  goal to the kinds of tool that check it.
- `setup-tree.sh` is optional, one line for most ecosystems (`bun install`,
  `uv sync`). It makes the current tree runnable: dependencies installed,
  local hooks wired. `worktree.sh add` runs it inside every fresh worktree,
  so the first verify never reds on a missing install. `land` runs it in the
  worktree before the suite when the primary branch changed a lockfile since
  the cut. It runs it in the primary tree after the fast-forward when the
  change touched a lockfile. A red run in the worktree fails the land. A red
  run in the primary tree after the merge is a warning, and the merge
  stands.
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
├── scripts/run-tests.sh         # the test adapter (plus optional typecheck/lint/proof/setup-tree)
├── .plans/<change>.md           # tracked; written at plan, deleted at consolidate
├── .plans/<change>/             # optional reference files for the Plan
├── .worktrees/<change>/         # gitignored; one per change in flight
├── .hone-durable-paths          # committed policy (optional)
├── .hone-irreversible-paths     # committed policy (optional)
├── .hone-proof-always           # committed policy (optional): prove every change
├── .hone-shared                 # committed policy (optional): the team's remote
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
├── templates/quality/           # which existing analyzer fits which goal
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
| garden      | P       | P    | P     | P/M        | P/M    | P/M    | W    |

Notes on the rarer cells: plan's reads are its step 2, where it reads the code,
the tests, and the area's Decisions and Notes. The Plan can then state what the
change replaces. plan's `(W)` on open questions covers only a new
question the Plan surfaces. Its `.git` write is the commit of the Plan
and its references on the primary branch. build's `.plans/` prune is a
reference promoted out, `git mv`'d next to the test that reads it. (build
is the only step that writes tests.) consolidate's `.plans/` prune is the `git rm` of the
Plan and any references build did not promote. garden is not part of a
change, but the standalone maintenance loop. Every column it touches is
a deletion, apart from the three `M` cells. Those carry its one non-deleting
change, the repair. It replaces a reference under `docs/` whose target moved,
one target for one target, and leaves the claim around it untouched. Code keeps
no `M`: a dangling reference in a `src/` comment sits beside code, and only
build writes code.

Spikes are outside the table, because a spike is not a change. Everything one
spike leaves behind lives under `docs/spikes/`, whatever its type. Examples:
the note, the probe code that produced it, a mockup, a captured payload, a
screenshot.
One spike is one dated stem, `<YYYY-MM-DD>-<slug>`, a single file where one
file is enough and a directory where it is not. No hook looks inside, so a
probe needs no test and no worktree, and nothing there has to keep the suite
green by itself.

Both `plan` (before a Plan exists) and `consolidate` (after the change) write a
spike. `docs/spikes/` and `docs/open-questions.md` are the two paths under
`docs/` the guard leaves writable in the primary tree, exactly as it leaves
`.plans/`. A probe and a plan-time open question both precede the Plan. Most
probes leave nothing behind: keep a spike only when its method or its dead
ends would save a future reader from running it again.

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
