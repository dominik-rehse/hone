# Dependency and toolchain refreshes

Background for a change whose subject is a version bump: a library, a linter, a
formatter, a build tool, a runtime. Read it at plan time when the sketch is such
a refresh, and at build time when the Plan says the change is one. Both skills
point here.

A refresh breaks three assumptions the normal loop makes. There is no failing
test to write first. The suite can stay green while the update is broken. The
package manager writes the files, so no command text names them. The shape below
replaces each assumption with something checkable.

This shape holds in every ecosystem. The commands are examples from JavaScript
and Python. Use the equivalent for the project's package manager.

## Plan time: probe, then pin the report

Probe read-only in the primary tree wherever you can. Reading a changelog, a
manifest, or the output of `bun outdated` or `npm outdated` installs nothing and
changes nothing.

Some probes need an install. Running the new linter to enumerate its findings
needs the new linter on disk. Do that in a throwaway detached worktree:

```bash
git worktree add --detach ../hone-probe HEAD   # any path outside the repo
# install and run the tool in that tree, read its output
git worktree remove --force ../hone-probe
```

Never install in the primary tree for a probe. Installing there and reverting
afterwards leaves the primary tree wrong for the whole probe. It also leaves the
installed packages wrong after the revert.

Put the probe's result in the Plan as data:

- the suite's exact counts today, per tier if the adapter reports tiers,
- every new finding the bumped tool reports, by file and line,
- the config keys the tool's migrator rewrites.

Frame that data as the expected report, not the authority. Write the frame into
the Plan in those words: "The expected result is 328 pass and 0 fail across 64
files. Any other count is a finding, not a new baseline." A tool that reports
something else has found something, and the loop must report it rather than
adopt it as the new normal. A long enumeration is a reference file under
`.plans/<slug>/`, not prose.

## The test-first exemption

A version bump has no red test to write first. It adds no behaviour to pin, so
there is nothing to fail. State that in the Plan in one line and name the
evidence instead:

- the suite at the same counts before and after, with the counts written down,
- the probe's report matched exactly,
- the verify additions below, each with its outcome.

Never write a test that asserts a version string. Such a test pins the manifest
to a copy of itself, fails on the next bump, and proves nothing about behaviour.
A refresh Plan with no red test and with its counts pinned as data is a
well-formed Plan.

## Build time

- **In-range bumps** go through the package manager's update command
  (`bun update`, `npm update`, `poetry update`). The range in the manifest is
  the decision. The update command applies it.
- **Range-crossing bumps** name each package explicitly (`bun add pkg@^3`,
  `npm install pkg@3`). Take one major at a time, so a break has one suspect.
- **Never sweep everything to latest.** `bun update --latest`,
  `npm-check-updates -u` across the whole manifest, and their equivalents have
  two failure modes seen in real repos. The sweep writes a literal `latest`
  specifier into the manifest and the lockfile, so the next install takes
  whatever the registry serves that day. And it jumps a package past a
  peer-version pin a dependent still holds, which resolves quietly and breaks at
  run time. Neither shows up in the diff as an error.
- **Config migrations go through the tool's own migrator**: `bunx biome migrate
  --write`, `bunx dprint config update`, and their equivalents. Check whether one
  exists before deciding the migration is manual. A hand edit misses renamed keys
  and changed defaults, and both stay silent.
- **Never write a version string into a manifest by hand.** The package manager
  writes the manifest and the lockfile together. A hand edit leaves the two out
  of step until someone installs, and the install then resolves something nobody
  chose.

## Verify time: three checks the gate cannot make

Run the normal gate first: the suite through `worktree.sh verify`, then
type-check and lint. Compare the suite's counts against the Plan's. Then add
these three, and state each one's outcome in the verify receipt.

**1. The lockfile is a fixed point.** A reinstall over a warm install reports "no
changes" because the packages are already there. That proves nothing. The honest
check is a cold install in a detached scratch worktree:

```bash
git worktree add --detach ../hone-lockcheck HEAD
# in that tree: install from scratch, with no installed packages present
git -C ../hone-lockcheck diff --exit-code <lockfile>
git worktree remove --force ../hone-lockcheck
```

A non-empty diff means the install rewrites the lockfile, so the next machine
resolves different versions. Fix the manifest until a cold install leaves the
lockfile alone.

**2. No duplicate nested copy.** An update can leave a second copy of a package
nested under a dependent, beside the top-level one. Types, tests, and lint all
stay green, and an `instanceof` or identity check across the two copies fails at
run time, because they are different objects. List the resolved copies of every
package you bumped (`npm ls <pkg>`, `bun pm ls --all`, `pip list`) and confirm
there is one of each. Where a duplicate is real, align the versions or record an
override or resolution.

**3. Tool caches are fresh.** A bumped tool often invalidates a cache it owns
outside the repo. A browser-automation package pins a browser build, the bump
leaves that build missing, and the e2e tier skips every test instead of failing.
The suite stays green and proves nothing. Refresh the cache the bumped tool owns
(`bunx playwright install` and its like) and confirm the affected tier ran a
non-zero count. A tier reporting `ran=0` is a red result here, not a pass.

## Land and after

`land` prints a receipt naming every lockfile the merge touched, and asks for a
reinstall in the primary tree. Do it. The merge updates the lockfile and installs
nothing. Until the reinstall, the primary tree runs the versions this change
replaced, and its next suite run tests the old install. A bare sync install
(`bun install`, `npm ci`, `poetry install`, flags only) passes the bash-guard
there. It installs what the lockfile already says, and it is the one dependency
command that belongs in the primary tree.
