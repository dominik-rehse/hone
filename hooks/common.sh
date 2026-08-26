#!/bin/bash
# Shared helpers for hone's hooks. The hooks (guard.sh, bash-guard.sh, gate.sh,
# nag.sh, session-start.sh) and the scripts that share their checks (setup.sh,
# worktree.sh) SOURCE this file, and nothing executes it directly. It defines
# functions only, and it has no side effects at source time. Keeping the JSON
# emit/escape, the stdin-field parse, and the deny-rule comparison in one place
# stops the consumers from drifting (they had already diverged).

# Escape a string for embedding as a JSON string value in a hook decision.
# The order: backslash first, then double-quote, then the control characters
# JSON spells out (newline, carriage return, tab). Prints the escaped text (no
# trailing newline).
#
# The function drops every remaining C0 control character. JSON forbids a raw
# control character inside a string, so one tab in a gate's output tail used
# to produce invalid JSON. The harness then discards the whole decision, and a
# blocking gate fails OPEN. A runner's progress output carries tabs and carriage returns
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

# Emit a block decision for a Stop or a PostToolUse hook (both read the same two
# fields). $1 = reason. The caller exits 0 afterwards.
hone_stop_block() {
    local reason
    reason=$(hone_json_escape "$1")
    printf '{"decision":"block","reason":"%s"}\n' "$reason"
}

# Extract a tool_input string field from a hook's JSON stdin. $1 = the raw JSON,
# $2 = the field name. Uses jq when available. The jq-less fallback uses `[^"]*`
# so it stops at the first closing quote, where a greedy `.*` would also match
# later fields. It cannot see through an escaped quote inside the value, so jq
# is the correct path and this is a best-effort degrade.
hone_extract_field() {
    local json="$1" field="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r --arg f "$field" '.tool_input[$f] // empty'
    else
        printf '%s' "$json" | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
    fi
}

# Extract a TOP-LEVEL string field from a hook's JSON stdin. $1 = the raw JSON,
# $2 = the field name. Same contract as hone_extract_field, one level up: that
# one reads .tool_input, and the fields the harness itself sets (cwd,
# session_id) sit beside it. The jq-less fallback is the same best-effort
# degrade, and it cannot tell the two levels apart.
hone_extract_top_field() {
    local json="$1" field="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r --arg f "$field" '.[$f] // empty'
    else
        printf '%s' "$json" | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
    fi
}

# True when path $1 is a durable committed artifact. That covers anything under
# src/, tests/, docs/, db/ (schema and migrations are as durable as code), or
# scripts/ (the adapters the gate runs live there). It covers the policy files
# themselves: an edit to them widens or shrinks the enforcement perimeter,
# which is a reviewed change, not a workspace edit. It also covers any path the
# project lists in the committed .hone-durable-paths (one per line, # comments
# allowed): a directory prefix (`deploy/`) or an exact file (`tsconfig.json`).
# The file EXTENDS the defaults: the built-in protected set can grow, never
# shrink.
#
# The .hone-proof-always marker counts as durable for the same reason. Deleting
# it is the cheapest way past the land proof gate, and the project's proof
# policy is not a workspace edit. .hone-review-always is durable for the same
# reason again: deleting it is the cheapest way to make a docs-only change skip
# its review.
#
# Reads .hone-durable-paths from the caller's cwd, so the caller cds to the
# project root first. guard.sh (the file-tool route) and dirty-guard.sh (the
# shell route) both call this, so the two routes can never protect different
# sets.
hone_is_durable() {
    case "$1" in
        # A spike note is dated, frozen history, and its author writes it
        # outside the loop like a Plan. Exploration usually precedes any Plan,
        # and often produces none, so the note has to be writable in the tree
        # where the probe ran. The built-in docs/ rule therefore skips it. A
        # project that wants it protected can still list it in
        # .hone-durable-paths, which the loop below still reads.
        docs/spikes/*) ;;
        # The plan skill records a plan-time open question in this ledger, and
        # /hone:plan runs in the primary tree. So the file has to be writable
        # where the Plan is written, exactly like a spike. The same
        # .hone-durable-paths escape hatch re-protects it for a project that
        # wants that.
        docs/open-questions.md) ;;
        src/*|tests/*|docs/*|db/*|scripts/*) return 0 ;;
        .hone-durable-paths|.hone-irreversible-paths|.hone-consequential-paths) return 0 ;;
        .hone-proof-always|.hone-review-always) return 0 ;;
    esac
    [ -f ".hone-durable-paths" ] || return 1
    local entry
    while IFS= read -r entry; do
        entry=$(printf '%s' "$entry" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case "$entry" in ''|'#'*) continue ;; esac
        entry="${entry%/}"
        case "$1" in
            "$entry"|"$entry"/*) return 0 ;;
        esac
    done < ".hone-durable-paths"
    return 1
}

# Print each canonical deny rule that appears in NEITHER settings file of
# project $1. $2 is the canonical list (templates/settings/deny-rules.txt: one
# rule per line, # comments). The match is semantic, not verbatim. A
# project-relative Edit rule counts in either legal spelling (Edit(./x) or
# Edit(x)). The check matches a rule as a whole JSON string ("..."), so a
# substring of a longer rule never counts. An inert Write(path) rule does not
# count either: Claude Code matches file tools against Edit(path) only, and it
# rejects a Write rule at startup. Extra deny rules beyond the canonical list
# are the project's business, and nothing here reports them. Empty output =
# complete.
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
