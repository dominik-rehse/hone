#!/bin/bash
# hone test adapter: Bun. Installed as scripts/run-tests.sh.
# Contract (see templates/run-tests/README.md):
#   run-tests.sh            → unit tier (the gate, refactor step)
#   run-tests.sh --all      → every tier (land, manual full runs)
#   run-tests.sh --unit     → unit tier, explicit
#   run-tests.sh <files...> → exactly those files (red/green loop)
#   exit 0 = all selected tests passed; non-zero = failures.
#
# Tier separation: slow/external tests live under integration/ or e2e/
# directories; the unit tier skips them.

# Read bun's own count back out of a run's output ("Ran N tests across M files").
ran_count() {
    local n
    n=$(grep -oE 'Ran [0-9]+ tests' "$1" 2>/dev/null | tail -n 1 | grep -oE '[0-9]+' || true)
    printf '%s' "${n:-0}"
}

# Run one tier and print its summary line, `hone tier: <name> ran=<count>`
# (see templates/run-tests/README.md). A tier that matches no test still exits
# 0, so land reads these lines and warns about any tier that ran nothing.
run_tier() {
    local tier="$1"; shift
    local log rc=0
    log=$(mktemp)
    "$@" 2>&1 | tee "$log" || rc=$?
    printf 'hone tier: %s ran=%s\n' "$tier" "$(ran_count "$log")"
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
        # Explicit files: run exactly those, no summary line.
        bun test "$@"
        return
    fi

    if [ "$mode" = "all" ]; then
        run_tier all bun test
    else
        # Unit tier: bun has no path-exclude flag, so restrict discovery to the
        # conventional roots that exist and let integration/e2e dirs be a
        # separate run. Adjust the roots to match your layout. Naming a root
        # that is absent makes bun error, and one run per tier keeps the
        # summary line honest, so pick the roots up front.
        if [ -d src ] && [ -d tests ]; then
            run_tier unit bun test src tests
        elif [ -d src ]; then
            run_tier unit bun test src
        elif [ -d tests ]; then
            run_tier unit bun test tests
        else
            run_tier unit bun test
        fi
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
