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

main() {
    set -euo pipefail
    local mode="unit"
    case "${1:-}" in
        --all)  mode="all";  shift ;;
        --unit) mode="unit"; shift ;;
    esac

    if [ "$#" -gt 0 ]; then
        bun test "$@"
        return
    fi

    if [ "$mode" = "all" ]; then
        bun test
    else
        # Unit tier: bun has no path-exclude flag, so restrict discovery to the
        # conventional roots and let integration/e2e dirs be a separate run.
        # Adjust the roots to match your layout.
        if [ -d src ] || [ -d tests ]; then
            bun test src tests 2>/dev/null || bun test
        else
            bun test
        fi
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
