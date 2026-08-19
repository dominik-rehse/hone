# Upgrading an existing hone repository

Moving a repo from an earlier hone version to the current one is three
mechanical steps.

1. *Take the new plugin version.* The marketplace distributes hone. Update
   it there, and the hooks and skills pick the change up automatically.

2. *Re-run setup.* Run `/hone:setup` in the repo, with you present. It runs
   the setup script, then executes each installed adapter and fixes what
   fails. That check matters most on an upgrade. The script alone never
   executes what it installs. So an adapter that has gone stale only fails
   later, mid-run, with nobody there to repair it.

   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"` is the non-interactive
   fallback. It is safe to repeat. It leaves your adapter, docs, and
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

After that, run `worktree.sh status`. It shows what is present and what is
missing. It also flags a policy file that is still uncommitted, and a
settings.json without the deny rules.

Two capabilities cost nothing until used, so enable them at any time:

- *`Governs:` links.* Add a `Governs:` line to a Decision or Note naming
  the `src/` path it explains. The nag then flags the doc when that path
  disappears. Add the lines as you next touch each doc. You need no
  upfront pass.
- *The garden loop.* Run `/hone:garden` between changes to trim stale
  docs, dead code, and redundant tests. Worth starting once there is
  enough written down to go stale.
