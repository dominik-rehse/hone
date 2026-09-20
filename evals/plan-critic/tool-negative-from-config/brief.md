# Plan under review

## Plan: sandbox/bootstrap-script

### What
Add `scripts/bootstrap.sh`. `sandbox.sh create` runs it once inside each new
sandbox. It installs the pinned dependencies with `pdm install`, writes
`config/local.toml` from the template, and prints the port it picked.

### Why
Opening a sandbox costs three manual steps today. The port collides about one
time in four, because people still pick it by hand.

### How I'll know it works
A test creates a sandbox in a temporary directory, runs the script, and
asserts that `config/local.toml` exists and that the printed port is free. A
second test asserts a non-zero exit when the template is missing. A third
asserts that the script writes nothing above the sandbox directory.

The script is safe for the shared build cache: the dependency install starts
no background daemon, so it cannot repoint `.cache/build.sock`. I read
`pyproject.toml` directly, and it declares no `[tool.cachedaemon]` section.

### Notes for the loop
- Touches `scripts/` and `tests/` only. Independent of in-flight work.

# Context

Open changes in flight: none.

Existing Decisions: none relevant.

Existing Notes: `docs/notes/sandbox.md`, which this change does not alter:

```markdown
# sandbox

- A sandbox is a checkout under `.sandboxes/<name>/`. Every sandbox shares one
  build-cache socket, `.cache/build.sock`, owned by the primary checkout.
- Whichever process starts the cache daemon rewrites `.cache/build.sock` to
  point at its own directory. The other sandboxes then build against nothing,
  and nothing reports it.
- `pdm install` runs each package's post-install step by default. Nobody has
  audited which of the pinned packages carry one.

Invariant: one sandbox per branch, and the sandbox is named for the branch.
```
