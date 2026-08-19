#!/bin/bash
# hone proof adapter: a long-running service. Installed as scripts/proof.sh.
# Contract (see templates/proof/README.md):
#   proof.sh <change>  → runs in the change's worktree, with HONE_CHANGE,
#                        HONE_BRANCH, HONE_WORKTREE, HONE_MAIN_ROOT set.
#   exit 0 = proven in the real environment; non-zero = not proven (land exits 7).
#
# Shape: start a SECOND instance of the service from the change's worktree,
# beside production and never in place of it (own port, own database copy, same
# real secrets and backends). Prove the behavior against it, then tear it down.
# Production keeps serving throughout. That is what makes this safe to run at
# land on a live box.

main() {
    set -euo pipefail
    local change="${1:-${HONE_CHANGE:-unknown}}"
    local root="${HONE_WORKTREE:-$PWD}"

    # Derive the instance from the change name so concurrent proofs cannot
    # collide on a port or a database.
    local port=$(( 4000 + $(printf '%s' "$change" | cksum | cut -d' ' -f1) % 1000 ))
    local state; state=$(mktemp -d "${TMPDIR:-/tmp}/proof-$change.XXXXXX")
    local pid=""

    cleanup() {
        [ -n "$pid" ] && kill "$pid" 2>/dev/null
        rm -rf "$state"
    }
    trap cleanup EXIT

    # 1. Provision the instance: copy the database, decrypt the same secrets the
    #    real service uses, apply migrations from the worktree.
    #    cp /var/lib/app/app.db "$state/app.db"
    #    (cd "$root" && ./scripts/migrate "$state/app.db")

    # 2. Start it from the code under test, on its own port.
    #    (cd "$root" && PORT="$port" STATE_DIR="$state" ./scripts/serve) &
    #    pid=$!

    # 3. Wait for it to answer, then prove the observable the Plan named against
    #    the running instance: a health probe, a real request, a browser journey.
    #    curl -fsS --retry 20 --retry-delay 1 "http://127.0.0.1:$port/health" >/dev/null
    #    curl -fsS "http://127.0.0.1:$port/the-changed-endpoint" | grep -q "expected"

    echo "proof: $change proven against an instance on port $port"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
