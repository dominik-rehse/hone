#!/bin/bash
# Mechanical proof that the shipped test adapters honour the tier-summary part
# of their contract (templates/run-tests/README.md): the line appears under
# --all only, it carries the RUNNER's own total, and an adapter that cannot read
# that total prints no line at all. A guessed count can never be 0, so it would
# silence land's empty-tier warning forever.
#
# Each template is sourced (its main runs only when executed), and the command
# it drives is replaced with a stub printing a real runner's summary. No node,
# bun, or pytest install is needed. Run: bash test/adapters_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
T="$PLUGIN_ROOT/templates/run-tests"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

# Run one adapter with its runner stubbed out. $1 = template, $2 = the stub body
# (a runner's output), $3.. = the adapter's arguments.
adapter_out() {
    local template="$1" output="$2"; shift 2
    ( . "$T/$template"
      run_tests() { printf '%s\n' "$output"; }   # node
      runner()    { printf '%s\n' "$output"; }   # python
      bun()       { printf '%s\n' "$output"; }   # bun
      main "$@" 2>&1 )
}

tier_line() { printf '%s\n' "$1" | grep -E '^hone tier:' | head -n 1; }

echo "== node: the runner's own total, under --all only =="
out=$(adapter_out node.sh "Tests:       12 passed, 12 total" --all)
[ "$(tier_line "$out")" = "hone tier: all ran=12" ] && ok "jest total parsed" || bad "jest total should give ran=12 (got '$(tier_line "$out")')"
out=$(adapter_out node.sh " Tests  3 passed (3)" --all)
[ "$(tier_line "$out")" = "hone tier: all ran=3" ] && ok "vitest total parsed" || bad "vitest total should give ran=3 (got '$(tier_line "$out")')"
out=$(adapter_out node.sh "# tests 5" --all)
[ "$(tier_line "$out")" = "hone tier: all ran=5" ] && ok "TAP total parsed" || bad "TAP total should give ran=5 (got '$(tier_line "$out")')"
out=$(adapter_out node.sh "  7 passing (12ms)" --all)
[ "$(tier_line "$out")" = "hone tier: all ran=7" ] && ok "mocha total parsed" || bad "mocha total should give ran=7 (got '$(tier_line "$out")')"
# A tier that really collected nothing reports it, and land warns.
out=$(adapter_out node.sh "Tests:       0 total" --all)
[ "$(tier_line "$out")" = "hone tier: all ran=0" ] && ok "an empty tier reports ran=0" || bad "an empty tier should report ran=0 (got '$(tier_line "$out")')"
# An unknown reporter: no line, rather than a count from the files on disk.
out=$(adapter_out node.sh "all good" --all)
[ -z "$(tier_line "$out")" ] && ok "an unrecognized reporter prints no tier line" || bad "an unknown total should print no tier line"
# The unit tier prints nothing: land is the only reader, and it runs --all.
out=$(adapter_out node.sh "Tests:       12 passed, 12 total")
[ -z "$(tier_line "$out")" ] && ok "the unit tier prints no tier line" || bad "the unit tier should print no summary line"
out=$(adapter_out node.sh "Tests:       12 passed, 12 total" --unit)
[ -z "$(tier_line "$out")" ] && ok "--unit prints no tier line" || bad "--unit should print no summary line"
# The runner's exit code survives the capture.
( . "$T/node.sh"; run_tests() { echo "Tests:       1 total"; return 3; }; main --all ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "the runner's exit code survives --all" || bad "--all should return the runner's exit (got $rc)"

echo "== python: pytest's collection count =="
out=$(adapter_out python.sh "collected 9 items" --all)
[ "$(tier_line "$out")" = "hone tier: all ran=9" ] && ok "pytest count parsed" || bad "pytest count should give ran=9 (got '$(tier_line "$out")')"
out=$(adapter_out python.sh "collected 0 items" --all)
[ "$(tier_line "$out")" = "hone tier: all ran=0" ] && ok "an empty pytest run reports ran=0" || bad "an empty pytest run should report ran=0"
out=$(adapter_out python.sh "ERROR: usage" --all)
[ -z "$(tier_line "$out")" ] && ok "no collection line means no tier line" || bad "an unparseable pytest run should print no tier line"
out=$(adapter_out python.sh "collected 9 items")
[ -z "$(tier_line "$out")" ] && ok "the unit tier prints no tier line" || bad "the python unit tier should print no summary line"

echo "== bun: bun's own count =="
out=$(adapter_out bun.sh "Ran 4 tests across 2 files" --all)
[ "$(tier_line "$out")" = "hone tier: all ran=4" ] && ok "bun count parsed" || bad "bun count should give ran=4 (got '$(tier_line "$out")')"
out=$(adapter_out bun.sh "error: no test files found" --all)
[ -z "$(tier_line "$out")" ] && ok "no Ran line means no tier line" || bad "an unparseable bun run should print no tier line"
out=$(adapter_out bun.sh "Ran 4 tests across 2 files")
[ -z "$(tier_line "$out")" ] && ok "the unit tier prints no tier line" || bad "the bun unit tier should print no summary line"

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
