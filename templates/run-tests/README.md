# Test adapter contract

`scripts/run-tests.sh` is the one language adapter that keeps hone's `gate` hook
language-agnostic. Install it with `/hone:setup` (which runs `scripts/setup.sh`
to pick a template here, then verifies it by executing it) or copy a template
and adapt it. It must honour this contract:

- `run-tests.sh` runs the *unit* tier: every fast test that needs nothing
  outside the repo (no network, no DB, no browser). This is what
  the `gate` runs and what the build loop's refactor step re-runs.
- `run-tests.sh --all` runs *every* tier, including slow or external
  integration/e2e tests (network, DB, browser). Run at land.
- `run-tests.sh --unit` runs the unit tier explicitly.
- `run-tests.sh <files...>` runs exactly those files (the red/green inner loop).
- Exit `0` = all selected tests passed. Any other exit means failures.
- Under `--all`, the adapter SHOULD print one summary line per tier it ran, in
  the form `hone tier: <name> ran=<count>`. Take the count from the runner's own
  reported total. An adapter that cannot read that total prints no line at all.

Keep slow or external tests out of the unit tier. Put them under an
`integration/` or `e2e/` directory, named so the runner still discovers them, or
the gate becomes flaky and gets bypassed.

## Tier summary lines

A tier that matches no test still exits `0`. The suite goes green and proves
nothing, and nobody sees it. The summary line makes that visible.

`land` reads these lines from the post-merge run and warns about every tier that
reported `ran=0`. The warning never blocks a land. An older adapter prints no
such lines, and `land` then says nothing.

`land` is the only reader, and it runs the adapter with `--all`, so print the
lines under `--all` alone. The gate runs the unit tier on every turn, and it
reads nothing here.

Print the count the runner itself reported, and nothing else. An adapter that
cannot parse that total must stay silent rather than guess. A file count is the
tempting guess and the wrong one. A file the runner skipped, or never collected,
still sits on disk, so such a count never reaches 0. It hides the exact failure
the line exists to show.

The shipped bun and python templates read the runner's own total. The node
template recognizes the common Node reporters, and prints no line for a reporter
it does not know.

## Type-check and lint (optional)

The gate also runs `scripts/typecheck.sh` and `scripts/lint.sh` *if they exist*
(exit `0` = clean). Add them where the language has them, for example a
`typecheck.sh` running `tsc --noEmit` or `mypy`/`pyright`, and a `lint.sh`
running `eslint` or `ruff`. There is no template: they are one line each and
project-specific.

`typecheck.sh` must cover **everything the repo compiles** (`src/`, `tests/`,
`scripts/`, tooling), not only production code. A tsconfig whose `include`
stops at `src/` makes the gate's green overstate its own reach. Type errors
then hide in exactly the code no test exercises, such as dev servers and deploy
tooling. They surface as broken tooling long after they landed.

## Real-environment proof (optional)

`scripts/proof.sh` is a *different* adapter from the test tiers: it proves a
change against the **real environment** (a browser journey, a canary, deployed
health). It runs only when a change declared `Proof: real-environment — <the check>`,
and only then at land. A green suite proves its assertions, not that the
deployed system behaves.

Its contract and templates live in `templates/proof/`: it is invoked as
`proof.sh <change>` from the change's worktree, so it can reach the code under
test. Without it, a real-environment change instead needs a human sign-off at
`.hone-proof/<change>` naming the commit it proved.
