#!/bin/bash
# hone project setup. Idempotent. Run once in a project that adopts hone:
#
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
#
# It installs the one test adapter (scripts/run-tests.sh) from the language
# template, gitignores the ephemeral artifacts (.worktrees/, markers), and
# creates the durable docs skeleton. It does NOT touch source, tests, or any
# existing adapter. An install that would overwrite scripts/run-tests.sh stops
# and tells you to diff instead. The optional type-check and lint adapters
# (scripts/typecheck.sh, scripts/lint.sh) are yours to add; the gate runs them
# when present.

set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR" || { echo "hone setup: cannot cd to $PROJECT_DIR" >&2; exit 1; }

echo "hone setup in $PROJECT_DIR"

# 1. Test adapter. Pick a template by the project's ecosystem. Check Bun FIRST:
# a Bun project also ships a package.json, so testing Node markers first would
# misdetect it as Node and install the wrong adapter.
mkdir -p scripts
TEMPLATE=""
if [ -f "bun.lockb" ] || [ -f "bun.lock" ] || [ -f "bunfig.toml" ]; then
    TEMPLATE="bun.sh"
elif [ -f "pnpm-lock.yaml" ] || [ -f "package-lock.json" ] || [ -f "yarn.lock" ] || [ -f "package.json" ]; then
    TEMPLATE="node.sh"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "setup.cfg" ] || ls ./*.py >/dev/null 2>&1; then
    TEMPLATE="python.sh"
fi

if [ -z "$TEMPLATE" ]; then
    echo "hone setup: could not detect the ecosystem. Copy a template from" >&2
    echo "  $PLUGIN_ROOT/templates/run-tests/ to scripts/run-tests.sh and adapt it to the contract (see that dir's README.md)." >&2
elif [ -f "scripts/run-tests.sh" ]; then
    echo "hone setup: scripts/run-tests.sh already exists — leaving it. Diff against $PLUGIN_ROOT/templates/run-tests/$TEMPLATE if you want the current template."
else
    cp "$PLUGIN_ROOT/templates/run-tests/$TEMPLATE" scripts/run-tests.sh
    chmod +x scripts/run-tests.sh
    echo "hone setup: installed scripts/run-tests.sh (from $TEMPLATE)."
fi

# 2. Gitignore the ephemeral artifacts. NOT .plans/: a Plan is committable now.
# It lands in git history, and consolidate removes it with a git rm the landing
# merge carries, so a prior setup's .plans/ ignore is stripped if present.
touch .gitignore
for entry in ".worktrees/" ".hone-off" ".hone-test-globs" ".hone-durable-paths" ".hone-gate-enforce" ".hone-nag-enforce" ".hone-authority-off" ".hone-consequential-paths" ".hone-grant/" ".hone-proof-off" ".hone-proof/"; do
    grep -qxF "$entry" .gitignore || printf '%s\n' "$entry" >> .gitignore
done
if grep -qxF ".plans/" .gitignore; then
    grep -vxF ".plans/" .gitignore > .gitignore.hone-tmp && mv .gitignore.hone-tmp .gitignore
    echo "hone setup: removed .plans/ from .gitignore — Plans are tracked now."
fi
echo "hone setup: ensured ephemeral artifacts are gitignored."

# 3. Durable docs skeleton (empty dirs are fine; the loop fills them), plus the
# src/ root. hone's enforcement keys off a src/<area>/ layout: the guard requires
# a test before code under src/, the nag maps each Note to a src/<area>/, and the
# gate watches src/ and tests/ for work in flight. Code must live under src/ for
# these to apply, Python packages included (src/<pkg>/ is a supported layout).
mkdir -p docs/decisions docs/notes .plans src
[ -f docs/open-questions.md ] || printf '# Open questions\n\nEmpirical bets only running code settles. Close or delete each entry once resolved; never grow it.\n' > docs/open-questions.md
echo "hone setup: created docs/decisions, docs/notes, docs/open-questions.md, .plans/, src/."

echo "hone setup: code lives under src/<area>/ — that is where the guard, gate, and nag apply."
echo "hone setup: done. Author a change with /hone:plan, then /hone:run."
