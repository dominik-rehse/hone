#!/bin/bash
# Shared helpers for hone's hooks. SOURCED by guard.sh, bash-guard.sh, gate.sh,
# and nag.sh — never executed directly. Defines functions only; no side effects
# at source time. Keeping the JSON emit/escape and the stdin-field parse in one
# place stops the four hooks from drifting (they had already diverged).

# Escape a string for embedding as a JSON string value in a hook decision:
# backslash first, then double-quote, then real newlines to the JSON `\n` escape.
# Prints the escaped text (no trailing newline).
hone_json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}

# Emit a PreToolUse decision. $1 = deny|ask, $2 = reason. The caller exits 0
# afterwards so this JSON is the sole channel (a non-zero exit would compete).
hone_pretool_decision() {
    local decision="$1" reason
    reason=$(hone_json_escape "$2")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
        "$decision" "$reason"
}

# Emit a Stop-hook block decision. $1 = reason. The caller exits 0 afterwards.
hone_stop_block() {
    local reason
    reason=$(hone_json_escape "$1")
    printf '{"decision":"block","reason":"%s"}\n' "$reason"
}

# Extract a tool_input string field from a hook's JSON stdin. $1 = the raw JSON,
# $2 = the field name. Uses jq when available. The jq-less fallback uses `[^"]*`
# so it stops at the first closing quote instead of a greedy `.*` swallowing
# later fields; it cannot see through an escaped quote inside the value, so jq is
# the correct path and this is a best-effort degrade.
hone_extract_field() {
    local json="$1" field="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r --arg f "$field" '.tool_input[$f] // empty'
    else
        printf '%s' "$json" | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
    fi
}
