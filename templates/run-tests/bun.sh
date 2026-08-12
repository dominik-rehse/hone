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
# Prints nothing when bun printed no such line: the contract says an adapter
# that cannot know the runner's count stays silent rather than guessing.
ran_count() {
    local n
    n=$(grep -oE 'Ran [0-9]+ tests' "$1" 2>/dev/null | tail -n 1 | grep -oE '[0-9]+' || true)
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
    "$@" 2>&1 | tee "$log" || rc=$?
    n=$(ran_count "$log")
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
        # Explicit files: run exactly those, no summary line.
        bun test "$@"
        return
    fi

    if [ "$mode" = "all" ]; then
        run_tier all bun test
        return
    fi

    # Unit tier: bun has no path-exclude flag, so restrict discovery to the
    # conventional roots that exist and let integration/e2e dirs be a separate
    # run. Adjust the roots to match your layout. Naming a root that is absent
    # makes bun error, so pick the roots up front. No summary line here: only
    # --all prints one.
    if [ -d src ] && [ -d tests ]; then
        bun test src tests
    elif [ -d src ]; then
        bun test src
    elif [ -d tests ]; then
        bun test tests
    else
        bun test
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
