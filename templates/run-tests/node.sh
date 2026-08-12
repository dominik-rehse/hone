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

# Count the test files the tier covers. Every Node runner prints its own
# summary and this adapter does not know which one the project uses, so a file
# count is the portable stand-in. Swap in your runner's own number where it
# prints one: a file the runner skipped still sits on disk.
count_test_files() {
    find . -name node_modules -prune -o \
        -type f \( -name '*.test.*' -o -name '*.spec.*' \) -print 2>/dev/null \
        | wc -l | tr -d ' '
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

    if [ "$#" -gt 0 ]; then
        # Explicit files: run exactly those, no summary line.
        run_tests "$@"
        return
    fi

    # One summary line per tier, `hone tier: <name> ran=<count>` (see
    # templates/run-tests/README.md). A tier that matches no test still exits
    # 0, so land reads these lines and warns about any tier that ran nothing.
    local rc=0
    run_tests || rc=$?
    printf 'hone tier: %s ran=%s\n' "$tier" "$(count_test_files)"
    return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
