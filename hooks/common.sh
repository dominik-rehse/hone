#!/bin/bash
# Shared helpers for hone's hooks. SOURCED by the hooks (guard.sh,
# bash-guard.sh, gate.sh, nag.sh, session-start.sh) and by the scripts that
# share their checks (setup.sh, worktree.sh), never executed directly. Defines
# functions only; no side effects at source time. Keeping the JSON emit/escape,
# the stdin-field parse, and the deny-rule comparison in one place stops the
# consumers from drifting (they had already diverged).

# Escape a string for embedding as a JSON string value in a hook decision:
# backslash first, then double-quote, then the control characters JSON spells
# out (newline, carriage return, tab). Prints the escaped text (no trailing
# newline).
#
# Every remaining C0 control character is dropped. JSON forbids a raw control
# character inside a string, so one tab in a gate's output tail used to produce
# invalid JSON. The harness then discards the whole decision, and a blocking
# gate fails OPEN. A runner's progress output carries tabs and carriage returns
# routinely, so this is the common case, not an exotic one.
hone_json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s" | tr -d '\001-\010\013\014\016-\037'
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

# Print each canonical deny rule that appears in NEITHER settings file of
# project $1. $2 is the canonical list (templates/settings/deny-rules.txt: one
# rule per line, # comments). The match is semantic, not verbatim: a
# project-relative Edit rule counts in either legal spelling (Edit(./x) or
# Edit(x)), matched as a whole JSON string ("...") so a substring of a longer
# rule never counts, and neither does an inert Write(path) rule (Claude Code
# matches file tools against Edit(path) only and rejects a Write rule at
# startup). Extra deny rules beyond the canonical list are the project's
# business; nothing here reports them. Empty output = complete.
hone_missing_deny_rules() {
    local project="$1" canon="$2" rule alt
    [ -f "$canon" ] || return 0
    while IFS= read -r rule; do
        rule=$(printf '%s' "$rule" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case "$rule" in ''|'#'*) continue ;; esac
        case "$rule" in
            'Edit(./'*) alt="Edit(${rule#"Edit(./"}" ;;
            *)          alt="$rule" ;;
        esac
        grep -qsF -e "\"$rule\"" -e "\"$alt\"" \
            "$project/.claude/settings.json" "$project/.claude/settings.local.json" \
            || printf '%s\n' "$rule"
    done < "$canon"
}
