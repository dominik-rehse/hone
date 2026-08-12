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

# Read pytest's own count back out of a run's output.
collected() {
    local n
    n=$(grep -oE 'collected +[0-9]+' "$1" 2>/dev/null | tail -n 1 | grep -oE '[0-9]+' || true)
    printf '%s' "${n:-0}"
}

# Run one tier and print its summary line, `hone tier: <name> ran=<count>`
# (see templates/run-tests/README.md). A tier that matches no test still exits
# 0, so land reads these lines and warns about any tier that ran nothing.
run_tier() {
    local tier="$1"; shift
    local log rc=0
    log=$(mktemp)
    runner "$@" 2>&1 | tee "$log" || rc=$?
    printf 'hone tier: %s ran=%s\n' "$tier" "$(collected "$log")"
    rm -f "$log"
    return "$rc"
}

main() {
    set -euo pipefail
    local mode="unit"
    case "${1:-}" in
        --all)  mode="all";  shift ;;
        --unit) mode="unit"; shift ;;
    esac

    if [ "$#" -gt 0 ]; then
        # Explicit files: run exactly those, no tier filtering and no summary.
        runner "$@"
        return
    fi

    if [ "$mode" = "all" ]; then
        run_tier all
    else
        # Unit tier: skip the integration/e2e directories, wherever they sit.
        run_tier unit \
            --ignore=integration --ignore=e2e \
            --ignore=tests/integration --ignore=tests/e2e
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
