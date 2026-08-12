#!/bin/bash
# hone test adapter: Node (npm / pnpm / yarn). Installed as scripts/run-tests.sh.
# Contract (see templates/run-tests/README.md):
#   run-tests.sh            → unit tier (the gate, refactor step)
#   run-tests.sh --all      → every tier (land, manual full runs)
#   run-tests.sh --unit     → unit tier, explicit
#   run-tests.sh <files...> → exactly those files (red/green loop)
#   exit 0 = all selected tests passed; non-zero = failures.
#
# The package manager runs the project's own "test" script; express tier
# separation there (a "test" script that ignores integration/ and e2e/).

detect_node_runner() {
    if [ -f pnpm-lock.yaml ];    then echo pnpm; return; fi
    if [ -f yarn.lock ];         then echo yarn; return; fi
    if [ -f package-lock.json ]; then echo npm;  return; fi
    local m
    for m in npm pnpm yarn; do
        command -v "$m" >/dev/null 2>&1 && { echo "$m"; return; }
    done
    echo none
}

run_tests() {
    local runner
    runner=$(detect_node_runner)
    case "$runner" in
        pnpm) pnpm test -- "$@" ;;
        npm)  npm test -- "$@" ;;
        yarn) yarn test "$@" ;;  # yarn does not use the `--` separator
        none)
            echo "ERROR: Node project detected, but none of pnpm, yarn, or npm is installed." >&2
            return 1 ;;
    esac
}

# Read the RUNNER's own test total out of a run's output ($1 = the log). This
# adapter does not know which runner the project uses, so it recognizes the
# common summaries and prints nothing when it recognizes none. Printing nothing
# is the contract: a guessed count (files on disk, say) can never be 0, and it
# would silence the very warning the line feeds. Add your runner's summary here.
ran_count() {
    local n=""
    # jest: "Tests:       12 passed, 12 total"
    n=$(grep -oE 'Tests:.*[0-9]+ total' "$1" 2>/dev/null | tail -n 1 \
        | grep -oE '[0-9]+ total' | grep -oE '[0-9]+')
    # vitest: "Tests  12 passed (12)"
    [ -n "$n" ] || n=$(grep -oE 'Tests +[0-9]+ [a-z]+ \([0-9]+\)' "$1" 2>/dev/null \
        | tail -n 1 | grep -oE '\([0-9]+\)' | grep -oE '[0-9]+')
    # node --test, and any other TAP reporter: "# tests 12"
    [ -n "$n" ] || n=$(grep -oE '^# tests [0-9]+' "$1" 2>/dev/null | tail -n 1 | grep -oE '[0-9]+')
    # mocha: "12 passing"
    [ -n "$n" ] || n=$(grep -oE '[0-9]+ passing' "$1" 2>/dev/null | tail -n 1 | grep -oE '[0-9]+')
    printf '%s' "$n"
}

main() {
    set -euo pipefail
    # --all / --unit accepted for a uniform CLI, then dropped: the project's own
    # "test" script owns tier selection. Express tiering there.
    local tier="unit"
    case "${1:-}" in
        --all)  tier="all";  shift ;;
        --unit) tier="unit"; shift ;;
    esac

    # Explicit files, and the unit tier, run bare: land is the only reader of
    # the summary line, so the gate's per-turn runs pay nothing for it.
    if [ "$#" -gt 0 ] || [ "$tier" != "all" ]; then
        run_tests "$@"
        return
    fi

    # --all prints one summary line, `hone tier: <name> ran=<count>` (see
    # templates/run-tests/README.md). A tier that matches no test still exits 0,
    # so land reads this line and warns about a tier that ran nothing.
    local log rc=0 n
    log=$(mktemp)
    run_tests 2>&1 | tee "$log" || rc=$?
    n=$(ran_count "$log")
    rm -f "$log"
    if [ -n "$n" ]; then printf 'hone tier: %s ran=%s\n' "$tier" "$n"; fi
    return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
