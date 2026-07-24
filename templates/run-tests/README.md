# Test adapter contract

`scripts/run-tests.sh` is the one language adapter that keeps hone's `gate` hook
language-agnostic. Install it with `scripts/setup.sh` (which picks a template
here) or copy a template and adapt it. It must honour this contract:

- `run-tests.sh` runs the *unit* tier: every fast test that needs nothing
  outside the repo (no network, no DB, no browser). This is what
  the `gate` runs and what the build loop's refactor step re-runs.
- `run-tests.sh --all` runs *every* tier, including slow or external
  integration/e2e tests (network, DB, browser). Run at land.
- `run-tests.sh --unit` runs the unit tier explicitly.
- `run-tests.sh <files...>` runs exactly those files (the red/green inner loop).
- Exit `0` = all selected tests passed; non-zero = failures.

Keep slow or external tests out of the unit tier. Put them under an
`integration/` or `e2e/` directory, named so the runner still discovers them, or
the gate becomes flaky and gets bypassed.

## Type-check and lint (optional)

The gate also runs `scripts/typecheck.sh` and `scripts/lint.sh` *if they exist*
(exit `0` = clean). Add them where the language has them, for example a
`typecheck.sh` running `tsc --noEmit` or `mypy`/`pyright`, and a `lint.sh`
running `eslint` or `ruff`. There is no template: they are one line each and
project-specific.

`typecheck.sh` must cover **everything the repo compiles** (`src/`, `tests/`,
`scripts/`, tooling), not only production code. A tsconfig whose `include`
stops at `src/` makes the gate's green overstate what was checked: type errors
hide in exactly the code no test exercises (dev servers, deploy tooling) and
surface as broken tooling long after they landed.

## Real-environment proof (optional)

`scripts/proof.sh` is a *different* adapter from the test tiers: it proves a
change against the **real environment** (a browser journey, a canary, deployed
health), not the working tree. It runs only when a change declared
`Proof: real-environment` (the proof gate is on by default; `.hone-proof-off`
disables it), and only then at land. A green suite proves its assertions, not
that the deployed system behaves. Exit `0` = proven. There is no template: what "the real
environment" means is project-specific (a Playwright run against a preview URL, a
`curl` of a canary's health endpoint). Without it, a real-environment change
instead needs a human sign-off at `.hone-proof/<change>`.
