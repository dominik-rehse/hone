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

# Read pytest's own count back out of a run's output. Prints nothing when
# pytest printed no collection line: the contract says an adapter that cannot
# know the runner's count stays silent rather than guessing.
collected() {
    local n
    n=$(grep -oE 'collected +[0-9]+' "$1" 2>/dev/null | tail -n 1 | grep -oE '[0-9]+' || true)
    printf '%s' "$n"
}

# Run one tier and print its summary line, `hone tier: <name> ran=<count>`
# (see templates/run-tests/README.md). A tier that matches no test still exits
# 0, so land reads these lines and warns about any tier that ran nothing.
# Only --all takes this path: land is the line's one reader, and the gate's
# per-turn unit runs should not pay for the capture.
run_tier() {
    local tier="$1"; shift
    local log rc=0 n
    log=$(mktemp)
    runner "$@" 2>&1 | tee "$log" || rc=$?
    n=$(collected "$log")
    rm -f "$log"
    if [ -n "$n" ]; then printf 'hone tier: %s ran=%s\n' "$tier" "$n"; fi
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
        # No summary line here: only --all prints one.
        runner --ignore=integration --ignore=e2e \
               --ignore=tests/integration --ignore=tests/e2e
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
