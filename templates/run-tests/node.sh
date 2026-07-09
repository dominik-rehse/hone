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

main() {
    set -euo pipefail
    # --all / --unit accepted for a uniform CLI, then dropped: the project's own
    # "test" script owns tier selection. Express tiering there.
    case "${1:-}" in
        --all|--unit) shift ;;
    esac
    run_tests "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
