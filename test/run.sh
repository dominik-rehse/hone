#!/bin/bash
# Run hone's mechanical test suite: the hook unit tests, the end-to-end land
# path, and the two checks on the message templates (prose and shape). These
# are deterministic (no model calls). The critic/rule evals are separate and
# live under evals/ (they call a model). Run: bash test/run.sh
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
rc=0
echo "### hooks_test.sh"
bash "$DIR/hooks_test.sh" || rc=1
echo
echo "### e2e_land_test.sh"
bash "$DIR/e2e_land_test.sh" || rc=1
echo
echo "### messages_lint.sh"
bash "$DIR/messages_lint.sh" || rc=1
echo
echo "### messages_shape.sh"
bash "$DIR/messages_shape.sh" || rc=1
echo
[ "$rc" -eq 0 ] && echo "test/run.sh: all green" || echo "test/run.sh: FAILURES above" >&2
exit "$rc"
