# Upgrading an existing hone repository

Moving a repo from an earlier hone version to the current one is three
mechanical steps.

1. *Take the new plugin version.* hone is distributed through the
   marketplace; update it there and the hooks and skills pick the change up
   automatically.

2. *Re-run setup.* Run `/hone:setup` in the repo, with you present. It runs
   the setup script, then executes each installed adapter and fixes what
   fails. That check matters most on an upgrade: the script alone never
   executes what it installs, so an adapter that has drifted out of date
   only fails later, mid-run, with nobody there to repair it.

   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"` is the non-interactive
   fallback. It is safe to repeat: it leaves your adapter, docs, and
   `.plans/` alone, keeps the per-developer files gitignored (`.hone-off`,
   `.hone-grant/`, `.hone-proof/`), and strips `.gitignore` entries for
   things hone no longer uses.

3. *Reconcile what your version predates.* Check each of these against
   [`reference.md`](reference.md):

   - *Markers removed in 0.19*: `.hone-test-globs`, `.hone-gate-enforce`,
     `.hone-nag-enforce`, `.hone-authority-off`, and `.hone-proof-off` do
     nothing anymore; delete them if present. The land gates now always run,
     and the way through them is the per-change grant or sign-off
     (`worktree.sh grant` / `attest`).
   - *Policy files are committed since 0.19*: `.hone-durable-paths` and
     `.hone-irreversible-paths` (rename yours from
     `.hone-consequential-paths`; the old name still works) are project
     config. Commit them so the whole team runs the same enforcement.
   - *Land exit codes changed in 0.20*: a merge conflict is exit 9 (2 now
     means only a usage or repo-state error). Update anything of yours that
     reads land's exit.
   - *The deny list is canonical since 0.24*: the plugin ships the full list
     (`templates/settings/deny-rules.txt`), grown beyond the four rules older
     READMEs prescribed. You don't reconcile it by hand: `setup.sh`, the
     session-start warning, and `worktree.sh status` each name exactly the
     rules your settings lack; paste them from the README's install block.

After that, run `worktree.sh status`: it shows what is installed, what is
missing, and flags a policy file that is still uncommitted or a settings.json
without the deny rules.

Two capabilities cost nothing until used, so enable them whenever:

- *`Governs:` links.* Add a `Governs:` line to a Decision or Note naming
  the `src/` path it explains, and the nag flags the doc when that path later
  disappears. Add them as you next touch each doc; no upfront sweep needed.
- *The garden loop.* Run `/hone:garden` between changes to trim stale docs,
  dead code, and redundant tests. Worth starting once there is enough written
  down to go stale.
