#!/bin/bash
# hone proof adapter: a CLI or batch tool. Installed as scripts/proof.sh.
# Contract (see templates/proof/README.md):
#   proof.sh <change>  → runs in the change's worktree, with HONE_CHANGE,
#                        HONE_BRANCH, HONE_WORKTREE, HONE_MAIN_ROOT set.
#   exit 0 = proven in the real environment; non-zero = not proven (land exits 7).
#
# Shape: run the real tool (the real external binary, the real API, no fakes)
# over a fixture the repo controls, into a scratch dir, and compare the output
# against what the change claims it should be. This is the tier the test suite
# cannot cover, so substituting a stub here defeats the point of the gate.

main() {
    set -euo pipefail
    local change="${1:-${HONE_CHANGE:-unknown}}"
    local root="${HONE_WORKTREE:-$PWD}"

    # A scratch instance named after the change: two changes can be proving at
    # once, and a shared output dir proves neither.
    local out; out=$(mktemp -d "${TMPDIR:-/tmp}/proof-$change.XXXXXX")
    trap 'rm -rf "$out"' EXIT

    # Preflight the real-world dependency. Failing here is the honest outcome:
    # "not proven" is correct when the environment to prove it in is absent.
    command -v SOME_REAL_BINARY >/dev/null 2>&1 || {
        echo "proof: SOME_REAL_BINARY is not on PATH, so it cannot prove $change against the real environment." >&2
        return 1
    }

    echo "proof: running $change against the real environment ($out)"

    # 1. Run the real thing from the code under test.
    #    (cd "$root" && ./your-cli convert test/fixtures/corpus "$out")

    # 2. Assert on what came out: the observable the Plan named, not a restated
    #    unit assertion.
    #    diff -r test/fixtures/expected "$out"

    echo "proof: $change proven"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
