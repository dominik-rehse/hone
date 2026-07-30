#!/bin/bash
# hone project setup: the deterministic mechanics. Safe to run again. The
# /hone:setup skill wraps it and then verifies the adapters by executing them;
# to run just the mechanics:
#
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
#
# It installs the one test adapter (scripts/run-tests.sh) from the language
# template, gitignores the temporary artifacts (.worktrees/, markers), and
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
    echo "hone setup: could not detect the ecosystem. Author scripts/run-tests.sh from the closest template in" >&2
    echo "  $PLUGIN_ROOT/templates/run-tests/ against the contract in that dir's README.md (/hone:setup does this for you)." >&2
elif [ -f "scripts/run-tests.sh" ]; then
    echo "hone setup: scripts/run-tests.sh already exists, so leaving it. Diff against $PLUGIN_ROOT/templates/run-tests/$TEMPLATE if you want the current template."
else
    cp "$PLUGIN_ROOT/templates/run-tests/$TEMPLATE" scripts/run-tests.sh
    chmod +x scripts/run-tests.sh
    echo "hone setup: installed scripts/run-tests.sh (from $TEMPLATE)."
fi

# 2. Gitignore the per-developer artifacts: the worktrees, the .hone-off kill
# switch, and the per-change grant/proof sign-offs. NOT .plans/ (a Plan is
# tracked; it lands in git history and consolidate removes it with a git rm the
# landing merge carries) and NOT the policy files (.hone-durable-paths,
# .hone-irreversible-paths): those are project policy, committed and shared.
# Entries an earlier hone version ignored (markers removed in 0.19, and the
# policy files back when they were per-developer) are stripped so they can be
# committed or deleted.
touch .gitignore
for entry in ".worktrees/" ".hone-off" ".hone-grant/" ".hone-proof/"; do
    grep -qxF "$entry" .gitignore || printf '%s\n' "$entry" >> .gitignore
done
for stale in ".plans/" ".hone-test-globs" ".hone-gate-enforce" ".hone-nag-enforce" \
             ".hone-authority-off" ".hone-proof-off" ".hone-durable-paths" \
             ".hone-consequential-paths" ".hone-irreversible-paths"; do
    if grep -qxF "$stale" .gitignore; then
        grep -vxF "$stale" .gitignore > .gitignore.hone-tmp && mv .gitignore.hone-tmp .gitignore
        echo "hone setup: removed $stale from .gitignore (tracked or retired in this hone version)."
    fi
done
echo "hone setup: ensured per-developer artifacts are gitignored."

# 3. Durable docs skeleton (empty dirs are fine; the loop fills them), plus the
# src/ root. hone's enforcement keys off a src/<area>/ layout: the guard requires
# a test before code under src/, the nag maps each Note to a src/<area>/, and the
# gate watches src/ and tests/ for work in flight. Code must live under src/ for
# these to apply, Python packages included (src/<pkg>/ is a supported layout).
mkdir -p docs/decisions docs/notes .plans src
[ -f docs/open-questions.md ] || printf '# Open questions\n\nAssumptions only running code can settle. Close or delete each entry once resolved; never grow it.\n' > docs/open-questions.md
echo "hone setup: created docs/decisions, docs/notes, docs/open-questions.md, .plans/, src/."

# 4. Report — never write — the settings deny rules. The block is installed by
# hand (README, Install) and /hone:setup completes it with the human present;
# a bare script run still names what is missing, so an upgrade that grew the
# canonical list surfaces here as one paste instead of an investigation.
# shellcheck source=hooks/common.sh
. "$PLUGIN_ROOT/hooks/common.sh"
MISSING_DENY=$(hone_missing_deny_rules "$PROJECT_DIR" "$PLUGIN_ROOT/templates/settings/deny-rules.txt")
if [ -n "$MISSING_DENY" ]; then
    echo "hone setup: .claude/settings.json is missing these deny rules (paste from the README's install block; add them last, after the adapters they protect are verified):"
    printf '%s\n' "$MISSING_DENY" | sed 's/^/  /'
else
    echo "hone setup: settings deny rules complete."
fi

echo "hone setup: code lives under src/<area>/; that is where the guard, gate, and nag apply."
echo "hone setup: for changes that need real-environment proof, copy a template from $PLUGIN_ROOT/templates/proof/ to scripts/proof.sh (optional; see that dir's README.md)."
echo "hone setup: done. Author a change with /hone:plan, then /hone:run."
