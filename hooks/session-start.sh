#!/bin/bash
# SessionStart hook (Claude Code). Two jobs:
#
# 1. Inject the lean workflow rule into the session context, read live from the
#    plugin. No file is written into the project, so the rule never goes stale,
#    never churns in git, and never fights the project's markdown formatter. A
#    legacy vendored copy at .claude/rules/<name>.md is honoured in place: it
#    loads natively, so it is NOT re-injected (no double-load).
#
# 2. Nudge a project that looks like it wants hone but has no test adapter to run
#    setup, so the gate has something to run.
#
# Disabled by the same .hone-off marker that turns off the rest of hone.
# Mechanism: SessionStart hook stdout is injected into the session context.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SOURCE_DIR="$SCRIPT_DIR/../rules"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# shellcheck source=hooks/common.sh
. "$SCRIPT_DIR/common.sh"
# shellcheck source=hooks/messages.sh
. "$SCRIPT_DIR/messages.sh"

[ -d "$SOURCE_DIR" ] || exit 0
[ -f "$PROJECT_DIR/.hone-off" ] && exit 0

FLAT_DIR="$PROJECT_DIR/.claude/rules"

# Strip YAML frontmatter and emit the rule body.
emit_rule() {
    awk '
        BEGIN { in_fm = 0; past_fm = 0; emitting = 0 }
        NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
        in_fm && /^---[[:space:]]*$/ { in_fm = 0; past_fm = 1; next }
        in_fm { next }
        past_fm && !emitting && /^[[:space:]]*$/ { next }
        { emitting = 1; print }
    ' "$1"
}

emitted=0
for f in "$SOURCE_DIR"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    # Honour a legacy tracked vendored copy: it loads natively, don't re-inject.
    [ -f "$FLAT_DIR/$name" ] && continue
    if [ "$emitted" -eq 0 ]; then
        printf '<!-- hone workflow rule (injected live from the plugin; edit upstream, not here) -->\n\n'
        emitted=1
    fi
    emit_rule "$f"
    printf '\n\n'
done

# A hone project carries durable artifacts (docs/decisions, docs/notes) or the
# temporary .plans/ but no test adapter → the gate can't run. Point at setup.
# These warnings go to STDOUT: a SessionStart hook's stdout is injected into
# the session context, so the model actually sees them; stderr on exit 0 is
# effectively invisible.
looks_like_hone=false
if [ -d "$PROJECT_DIR/docs/decisions" ] || [ -d "$PROJECT_DIR/docs/notes" ] || [ -d "$PROJECT_DIR/.plans" ]; then
    looks_like_hone=true
fi

if [ "$looks_like_hone" = true ] && [ ! -f "$PROJECT_DIR/scripts/run-tests.sh" ]; then
    msg_session_no_adapter
fi

# hone keys its enforcement off a src/<area>/ layout. A hone project with no src/
# means the guard, gate, and nag silently do nothing. Surface that instead of
# leaving it a silent gap.
if [ "$looks_like_hone" = true ] && [ ! -d "$PROJECT_DIR/src" ]; then
    msg_session_no_src
fi

# The settings deny rules are the file-tool half of hone's tamper resistance
# for the adapters (the bash-guard closes the shell routes). They are
# installed by hand, so nothing else notices when they are missing. A plugin
# upgrade that grew the canonical list leaves them incomplete the same way.
# Compare against the canonical list semantically (hone_missing_deny_rules:
# either settings file, either spelling of a relative path) and name exactly
# what is missing, so an upgrade is one paste instead of an investigation.
if [ "$looks_like_hone" = true ]; then
    missing=$(hone_missing_deny_rules "$PROJECT_DIR" "$SCRIPT_DIR/../templates/settings/deny-rules.txt")
    if [ -n "$missing" ]; then
        msg_session_missing_deny "$missing"
    fi
fi

exit 0
