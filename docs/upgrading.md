# Upgrading an existing hone repository

Moving a repo from an earlier hone version to the current one is three
mechanical steps.

1. *Take the new plugin version.* The marketplace distributes hone. Update
   it there, and the hooks and skills pick the change up automatically.

2. *Re-run setup.* Run `/hone:setup` in the repo, with you present. It runs
   the setup script, then executes each installed adapter and fixes what
   fails. That check matters most on an upgrade. The script alone never
   executes what it installs, so an adapter that has gone stale only fails
   later, mid-run, with nobody there to repair it.

   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"` is the non-interactive
   fallback. It is safe to repeat, and it leaves your adapter, docs, and
   `.plans/` alone. It keeps the per-developer files gitignored
   (`.hone-off`, `.hone-grant/`, `.hone-proof/`). And it strips
   `.gitignore` entries for things hone no longer uses, `spikes/` from
   0.33 among them.

3. *Reconcile what your version predates.* Check each of these against
   [`reference.md`](reference.md):

   - *Markers removed in 0.19*: `.hone-test-globs`, `.hone-gate-enforce`,
     `.hone-nag-enforce`, `.hone-authority-off`, and `.hone-proof-off` do
     nothing anymore. Delete them if present. The land gates now always
     run, and the way through them is the per-change grant or sign-off
     (`worktree.sh grant` / `attest`).
   - *Policy files are project config since 0.19*: `.hone-durable-paths`
     and `.hone-irreversible-paths` belong in the repo. Rename yours from
     `.hone-consequential-paths`, though the old name still works. Commit
     them so the whole team runs the same enforcement.
   - *Land exit codes changed in 0.20*: a merge conflict is exit 9 (2 now
     means only a usage or repo-state error). Update anything of yours
     that reads land's exit.
   - *The deny list is canonical since 0.24*: the plugin ships the full
     list (`templates/settings/deny-rules.txt`), grown beyond the four
     rules older READMEs prescribed. You do not reconcile it by hand.
     `setup.sh`, the session-start warning, and `worktree.sh status` each
     name exactly the rules your settings lack. Paste them from the
     README's install block.
   - *`/hone:herd` is gone in 0.35*: `/hone:run --all` now detects herdr
     itself and spreads the plans over tabs. Type that instead. The
     `--workspace` flag went with the command: create the workspace
     yourself and invoke `--all` in it. Nothing to install.
   - *A new hook in 0.26*: `dirty-guard` blocks a shell command that
     leaves a protected path dirty in the primary tree. Claude Code reads
     the hook set once, at session start, so restart every session in the
     repo before this takes effect. The same restart picks up the workflow
     rule this version adds. Nothing to install and nothing to configure.
   - *Check configs ask in any tree since 0.50*: the guard and the
     bash-guard ask before an edit to a test-runner, linter, formatter, or
     type-checker config. Examples are `biome.json`, `tsconfig.json`, and
     `bunfig.toml`, and `reference.md` has the full list. They ask in a
     worktree as well as in the primary tree. A repo that listed such files in
     `.hone-durable-paths` keeps the listing: it still adds the
     primary-tree deny and the dirty-guard check, which the ask does not.
     The bash-guard also stops reading a commit message or a sign-off text
     as the act it names, so a message that documents `--no-verify` passes.
     Nothing to install and nothing to configure.
   - *Shared mode since 0.51*: a team commits a `.hone-shared` marker, and
     land then pushes the tested merge to the remote it names. Nothing
     changes without the marker. Turn it on with no worktree in flight and
     the primary branch pushed. Then no branch was cut from a commit that a
     later rebase moves. The remote must accept pushes to `refs/hone/*`.
   - *Model IDs are pinned since 0.53*: the critics and the nested
     `/code-review` name a full model ID where they named the `sonnet`
     and `opus` aliases. Nothing to do on the Anthropic API. On a provider
     that names its models differently, read the pin paragraph under
     *Commands* in `reference.md`.
   - *The critics run on opus since 0.54*: `plan-critic` and
     `consolidate-critic` pin claude-opus-5 where they pinned
     claude-sonnet-5. A Plan review costs more, and the `plan-critic`
     sends more Plans back at plan time. Each bounce names a concrete gap,
     often a fork that the Plan left to the loop. Nothing to install.
   - *The review names its level since 0.53.1*: the loop's nested
     `/code-review` now runs at `high`. Before, it ran at whichever level
     you typed last in any session, because the prompt named none. A review
     costs more than before if that level was lower. Nothing to install
     and nothing to configure.

   - *Land demands the `Cut:` line since 0.55*: `worktree.sh land` refuses a
     branch on which no commit body carries `Cut: <what>` (or `Repair: <what>`
     for a garden repair), with exit 2. A change that removed nothing writes
     `Cut: nothing` and the reason. Since 0.55.1 a bare `Cut: nothing` and a
     placeholder in angle brackets do not count. The loop writes the line
     already. A worktree that was in flight during the upgrade may lack it.
     Amend its commit as the refusal says, and land again. A script of yours
     that lands a branch must write the line too.
   - *Two more things since 0.55 need nothing from you*: the nag names a
     `src/<area>/` over `HONE_AREA_MAX_LINES` (default 3000) when a change
     about to land touched it. Since 0.56 `/hone:garden` names such an area
     across the whole repo, and puts it into a proposed Plan. And the loop
     hands the `consolidate-critic` every Note and Decision about the changed
     code, which `worktree.sh governed` lists. A `Governs:` line on a Decision
     is what puts it on that list, so the lines are worth more than before.

After that, run `worktree.sh status`. It shows what is present and what is
missing. It also flags a policy file that is still uncommitted, and a
settings.json without the deny rules.

Two capabilities cost nothing until used, so enable them at any time:

- *`Governs:` links.* Add a `Governs:` line to a Decision or Note naming
  the `src/` path it explains. The nag then flags the doc when that path
  disappears. Add the lines as you next touch each doc. You need no
  upfront pass.
- *The garden loop.* Run `/hone:garden` between changes to trim stale
  docs, dead code, and redundant tests, and to repoint a `docs/`
  reference whose target moved. Worth starting once there is enough
  written down to go stale.
