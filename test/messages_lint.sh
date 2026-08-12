#!/bin/bash
# Lint hone's message prose. hooks/messages.sh --dump prints every template
# once as Markdown, with the commands in fenced blocks, and the ste linter
# checks the sentence-level rules the messages follow: 25 words or fewer per
# sentence, no semicolons, plain words. Run: bash test/messages_lint.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)

# Resolve the linter: an explicit override first, then the working copy, then
# the installed plugin. A missing linter FAILS the suite rather than skipping
# quietly, because a silent skip ships the messages unchecked.
LINT=""
for candidate in "${STE_LINT:-}" \
                 "/home/dominik/repos/ste/hooks/ste_lint.py" \
                 "$HOME/.claude/plugins/marketplaces/ste/hooks/ste_lint.py"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then LINT="$candidate"; break; fi
done
if [ -z "$LINT" ]; then
    echo "  FAIL no ste linter found. Point STE_LINT at ste_lint.py, or install the ste plugin." >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
DUMP="$WORK/messages.md"

bash "$PLUGIN_ROOT/hooks/messages.sh" --dump > "$DUMP" || {
    echo "  FAIL messages.sh --dump did not run" >&2; exit 1; }

out=$(python3 "$LINT" --check "$DUMP" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
    printf '  ok   message prose passes the ste lint (%s)\n' "$LINT"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/       /'
    exit 0
fi
printf '%s\n' "$out" | sed 's/^/  /'
echo "  FAIL the message templates have blocking ste findings (above)" >&2
exit 1
