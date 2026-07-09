#!/bin/bash
# hone test adapter: Python (pytest). Installed as scripts/run-tests.sh.
# Contract (see templates/run-tests/README.md):
#   run-tests.sh            → unit tier (the gate, refactor step)
#   run-tests.sh --all      → every tier (land, manual full runs)
#   run-tests.sh --unit     → unit tier, explicit
#   run-tests.sh <files...> → exactly those files (red/green loop)
#   exit 0 = all selected tests passed; non-zero = failures.
#
# Tier separation: slow/external tests live under integration/ or e2e/
# directories; the unit tier deselects them by path.

runner() {
    if command -v uv >/dev/null 2>&1 && [ -f pyproject.toml ]; then
        uv run pytest "$@"
    elif command -v pytest >/dev/null 2>&1; then
        pytest "$@"
    else
        python -m pytest "$@"
    fi
}

main() {
    set -euo pipefail
    local mode="unit"
    case "${1:-}" in
        --all)  mode="all";  shift ;;
        --unit) mode="unit"; shift ;;
    esac

    if [ "$#" -gt 0 ]; then
        # Explicit files: run exactly those, no tier filtering.
        runner "$@"
        return
    fi

    if [ "$mode" = "all" ]; then
        runner
    else
        # Unit tier: skip the integration/e2e directories, wherever they sit.
        runner \
            --ignore=integration --ignore=e2e \
            --ignore=tests/integration --ignore=tests/e2e
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
