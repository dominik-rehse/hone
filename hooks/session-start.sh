#!/bin/bash
# SessionStart hook (Claude Code). Two jobs:
#
# 1. Inject the lean workflow rule into the session context, read live from the
#    plugin. The hook writes no file into the project, so the rule never goes
#    stale, never churns in git, and never conflicts with the project's
#    markdown formatter. The hook honours a legacy vendored copy at
#    .claude/rules/<name>.md in place: it loads natively, so the hook does NOT
#    re-inject it (no double-load).
#
# 2. Tell a project that looks like it wants hone but has no test adapter to
#    run setup, so the gate has something to run.
#
# 3. In the primary tree, show what needs the person: the lines of
#    `worktree.sh attention` (hooks/hygiene.sh has the checks). Not in a
#    linked worktree, where a run works, and not in a nested review session.
#
# The same .hone-off marker that disables the rest of hone disables this hook.
# Mechanism: the hook prints one JSON object, or nothing. Its
# hookSpecificOutput.additionalContext reaches the model only, and carries the
# rule and the warnings. Its systemMessage reaches the person only, and carries
# the warnings, because they ask the person to act. Plain stdout would reach
# the model only.

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

context=""
warnings=""
# Append text $2 to the variable named $1, a blank line between parts.
add() {
    local cur="${!1}"
    printf -v "$1" '%s' "${cur:+$cur

}$2"
}

emitted=0
for f in "$SOURCE_DIR"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    # Honour a legacy tracked vendored copy: it loads natively, so do not re-inject it.
    [ -f "$FLAT_DIR/$name" ] && continue
    if [ "$emitted" -eq 0 ]; then
        add context '<!-- hone workflow rule (injected live from the plugin; edit upstream, not here) -->'
        emitted=1
    fi
    add context "$(emit_rule "$f")"
done

# A hone project carries durable artifacts (docs/decisions, docs/notes) or the
# temporary .plans/ but no test adapter → the gate cannot run. Point at setup.
# Each warning goes to both readers (see the header). Stderr on exit 0 reaches
# neither.
looks_like_hone=false
if [ -d "$PROJECT_DIR/docs/decisions" ] || [ -d "$PROJECT_DIR/docs/notes" ] || [ -d "$PROJECT_DIR/.plans" ]; then
    looks_like_hone=true
fi

if [ "$looks_like_hone" = true ] && [ ! -f "$PROJECT_DIR/scripts/run-tests.sh" ]; then
    add warnings "$(msg_session_no_adapter)"
fi

# hone keys its enforcement off a src/<area>/ layout. A hone project with no src/
# means the guard and the gate silently do nothing. Report that instead of
# leaving it a silent gap.
if [ "$looks_like_hone" = true ] && [ ! -d "$PROJECT_DIR/src" ]; then
    add warnings "$(msg_session_no_src)"
fi

# Before 0.81.0 open questions lived in one shared file with numbered entries.
# Parallel changes conflicted on it at land and took the same next number. A
# project that still has it needs a migration that takes judgment, so say so.
if [ "$looks_like_hone" = true ] && [ -f "$PROJECT_DIR/docs/open-questions.md" ]; then
    add warnings "$(msg_session_old_open_questions)"
fi

# The settings deny rules are the file-tool half of hone's tamper resistance
# for the adapters (the bash-guard closes the shell routes). The human
# installs them by hand, so nothing else notices when they are missing. A
# plugin upgrade that grew the canonical list leaves them incomplete the same
# way. Compare against the canonical list semantically (hone_missing_deny_rules:
# either settings file, either spelling of a relative path). Name exactly
# what is missing, so an upgrade is one paste instead of an investigation.
if [ "$looks_like_hone" = true ]; then
    missing=$(hone_missing_deny_rules "$PROJECT_DIR" "$SCRIPT_DIR/../templates/settings/deny-rules.txt")
    if [ -n "$missing" ]; then
        add warnings "$(msg_session_missing_deny "$missing")"
    fi
fi

[ -n "$warnings" ] && add context "$warnings"

# What needs the person, in the primary tree only (its git dir is the common
# dir). The person reads it. The model gets it too, marked as the person's, so
# it can answer a question about it. A timeout keeps the hook inside its own.
person="$warnings"
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 && ! hone_nested_review; then
    git_dir=$(git -C "$PROJECT_DIR" rev-parse --absolute-git-dir 2>/dev/null)
    common_dir=$(cd "$PROJECT_DIR" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
    if [ -n "$git_dir" ] && [ "$(cd "$git_dir" && pwd -P)" = "$common_dir" ]; then
        # The payload carries the session id. A terminal on stdin carries none.
        t=()
        command -v timeout >/dev/null 2>&1 && t=(timeout 3)
        payload=""
        if [ ! -t 0 ]; then
            if command -v timeout >/dev/null 2>&1; then payload=$(timeout 1 cat 2>/dev/null)
            else payload=$(cat 2>/dev/null); fi
        fi
        session=$(hone_extract_top_field "$payload" session_id 2>/dev/null)
        attention=$(cd "$PROJECT_DIR" && ${t[@]+"${t[@]}"} bash "$SCRIPT_DIR/../scripts/worktree.sh" attention \
            ${session:+--session "$session"} 2>/dev/null)
        if [ -n "$attention" ]; then
            add person "$(msg_session_attention_heading)
$attention"
            add context "$(msg_session_attention_context)
$attention"
        fi
    fi
fi

[ -n "$context" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}' "$(hone_json_escape "$context")"
[ -n "$person" ] && printf ',"systemMessage":"%s"' "$(hone_json_escape "$person")"
printf '}\n'
exit 0
