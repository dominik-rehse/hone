#!/bin/bash
# Shared helpers for hone's hooks. The hooks (guard.sh, bash-guard.sh, gate.sh,
# nag.sh, session-start.sh, progress.sh, watch.sh) and the scripts that share their checks (setup.sh,
# worktree.sh, coordinate.sh) SOURCE this file, and nothing executes it directly. It defines
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
# blocking gate fails OPEN. A runner's progress output carries tabs and
# carriage returns routinely, so this is the common case.
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

# Emit a block decision for a Stop, PostToolUse, or PostToolUseFailure hook (all
# read the same two fields). $1 = reason. The caller exits 0 afterwards.
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
# its review. .hone-shared is durable too: deleting it is the cheapest way
# past a push the host refused, and where the team lands is not a workspace
# edit. .hone-grant-auto is durable because creating it lets every
# irreversible change land with no person.
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
        .hone-proof-always|.hone-review-always|.hone-shared|.hone-grant-auto) return 0 ;;
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

# The config files the gate's checks read. A test, lint, format, or type-check
# run is only as strict as its config, so an edit to one is the cheapest way
# from red to green without touching the code: exclude a test file, silence a
# rule, add a path to an ignore list, drop `strict`. The two routes (guard.sh for the file tools,
# bash-guard.sh for the shell) both escalate such an edit, in ANY tree, on this
# one definition. It is an ERE over the basename, so a nested config in a
# monorepo counts too. The list is the dedicated config files only. A manifest
# that also carries tool settings (package.json, pyproject.toml, setup.cfg) is
# not here, because most edits to one are ordinary dependency work.
HONE_CHECK_CONFIG_RE='(bunfig\.toml|vitest\.(config|workspace)\.[a-z]+|jest\.config\.[a-z]+|pytest\.ini|\.coveragerc|stryker\.(config|conf)\.[a-z]+|\.eslintrc(\.[a-z]+)?|eslint\.config\.[a-z]+|\.eslintignore|\.prettierrc(\.[a-z]+)?|prettier\.config\.[a-z]+|\.prettierignore|biome\.jsonc?|\.?dprint\.jsonc?|\.?ruff\.toml|\.flake8|\.?mypy\.ini|pyrightconfig\.json|tsconfig(\.[a-z0-9-]+)?\.json|\.shellcheckrc|\.markdownlint(rc|\.[a-z]+)|\.stylelintrc(\.[a-z]+)?|stylelint\.config\.[a-z]+|\.golangci\.ya?ml|\.?rustfmt\.toml|clippy\.toml)'

# True when path $1 (project-relative) is one of the check configs above.
hone_is_check_config() {
    printf '%s\n' "${1##*/}" | grep -Eq "^${HONE_CHECK_CONFIG_RE}\$"
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

# The path-shaped tokens of a document's `Governs:` line, one per line. The
# line is optional, and only a token with a "/" counts as a path. The parse
# strips backticks, commas, and a trailing period, so
# `Governs: `src/auth/token.ts`, ...` parses. A token may be a glob. It expands
# against ROOT ($2, default the current directory), which is the tree that the
# document belongs to. A glob that matches nothing stays as written.
hone_governs_paths() {
    local gov
    gov=$(grep -im1 '^[[:space:]]*governs:' "$1" 2>/dev/null | sed 's/.*[Gg]overns:[[:space:]]*//')
    gov=${gov//\`/}
    gov=${gov//,/ }
    (
        cd "${2:-.}" 2>/dev/null || exit 0
        # shellcheck disable=SC2086  # the split and the glob are wanted here
        for tok in $gov; do
            tok=${tok%.}
            case "$tok" in */*) printf '%s\n' "$tok" ;; esac
        done
    )
}

# Append one event to the coordinate event file (scripts/coordinate.sh). $1 =
# the state directory (<git-common-dir>/hone-coordinate), $2 = the change,
# $3 = the kind, $4 = the detail. Without the directory nobody watches, so
# nothing is written. The lock keeps the event numbers unique when land and
# the ticker write at once. A tab or a newline in the detail would break the
# line, so they become spaces.
hone_coord_event() {
    local dir="$1" detail="${4//[$'\t\n']/ }"
    [ -d "$dir" ] || return 0
    (
        command -v flock >/dev/null 2>&1 && flock -w 5 9
        n=0
        [ -f "$dir/events" ] && n=$(awk -F'\t' 'END { print $1 + 0 }' "$dir/events")
        printf '%s\t%s\t%s\t%s\t%s\n' "$((n + 1))" "$(date +%s)" "$2" "$3" "$detail" >> "$dir/events"
        hone_coord_skew "$dir" "$((n + 2))"
    ) 9>"$dir/events.lock" 2>/dev/null
    return 0
}

# The version of this copy of hone, from its plugin.json.
hone_version() {
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$(dirname -- "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json" 2>/dev/null | head -1
}

# A coordinator loads its scripts once, at session start. When a newer hone
# writes to its event file, append one `updated` event, numbered $2, that
# tells it to restart. Its own wait prints the event, so this works with a
# coordinator of any version. The watch record names the coordinator's
# version, and a record with none is from before the field existed.
# $1 = the state directory. Once per writing version.
hone_coord_skew() {
    local dir="$1" wv cv f old="" sid how
    wv=$(hone_version)
    [ -n "$wv" ] && [ ! -e "$dir/updated.$wv" ] || return 0
    for f in "$dir"/sessions/*; do
        [ -f "$f" ] || continue
        cv=$(sed -n 's/^version=//p' "$f" | head -1)
        [ "$cv" = "$wv" ] && continue
        [ "$(printf '%s\n%s\n' "${cv:-0}" "$wv" | sort -V | tail -1)" = "$wv" ] || continue
        old=${cv:-"a hone from before $wv"}
        sid=$(sed -n 's/^owner=//p' "$f" | head -1)
        break
    done
    [ -n "$old" ] || return 0
    : > "$dir/updated.$wv"
    # The watches belong to the coordinator's session id. A resume keeps
    # the id, and a fresh session gets a new one that owns no watch.
    how="with claude --resume${sid:+ $sid} in its tab, so it keeps its watches"
    printf '%s\t%s\thone\tupdated\t%s\n' "$2" "$(date +%s)" \
        "hone $wv wrote here, and the coordinator runs $old. Restart the coordinator session $how." >> "$dir/events"
}

# ------------------------------------------------------------ suite lock

# The start time of process $1, so a ticket outlives no reused pid. Empty
# when the system cannot tell.
hone_pid_start() {
    if [ -r "/proc/$1/stat" ]; then
        sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f20
    else
        ps -o lstart= -p "$1" 2>/dev/null
    fi
}

# Print the first live ticket in the queue directory $1, and delete every
# dead ticket before it. A ticket is named <class>.<seq>.<pid>, so the sort
# puts a land (class 0) before a suite (class 1), and each class in arrival
# order. A ticket whose process is gone, or whose pid now names another
# process, is a waiter that died. It must not hold the queue.
hone_queue_head() {
    local t pid
    for t in "$1"/[01].*.*; do
        [ -f "$t" ] || continue
        pid=${t##*.}
        if kill -0 "$pid" 2>/dev/null \
           && [ "$(hone_pid_start "$pid")" = "$(cat "$t" 2>/dev/null)" ]; then
            printf '%s\n' "$t"
            return 0
        fi
        rm -f "$t" 2>/dev/null
    done
    return 0
}

# Exit 0 when the taker that last took the lock through the queue
# ($1/holder) is still alive. The lock frees when that process ends.
hone_queue_holder_live() {
    local pid st
    read -r pid st 2>/dev/null <"$1/holder" || return 1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null \
        && [ "$(hone_pid_start "$pid" | tr -d ' ')" = "${st// /}" ]
}

# Take the suite lock on fd 9, in arrival order. $1 = the lock file, $2 = the
# wait in seconds, $3 = `land` for a step that moves the primary tree, else
# `suite`. Exit 0 held · 2 lock file unopenable · 5 timeout.
#
# flock alone is no queue. When the holder lets go, every waiter races, and
# a verify that came later can win. Under parallel runs new verifies kept
# winning, and one land timed out seven times in two hours. So each taker
# first writes a ticket into <lock>.queue/, and only the first live ticket
# calls flock. A land goes before a suite, because a land ends a change and
# frees its run. The head polls flock in steps of one second, so a land that
# arrives while a suite waits at the head still goes first. The wait in $2
# covers the queue and the flock together. For a land it counts only while
# the queue stands still (see the loop). A taker that holds the lock
# deletes its ticket, and a dead taker's ticket is skipped.
hone_suite_lock() {
    local lock="$1" timeout="$2" class="$3" q pri seq me head left start
    # The braces keep the 2>/dev/null off exec, which would make it stick.
    { exec 9>"$lock"; } 2>/dev/null || return 2
    q="$lock.queue"
    # A wait that is not whole seconds, or a queue that cannot be made, takes
    # the plain flock, as before the queue.
    case "$timeout" in ''|*[!0-9]*) flock -w "$timeout" 9 && return 0; return 5 ;; esac
    mkdir -p "$q" 2>/dev/null || { flock -w "$timeout" 9 && return 0; return 5; }
    pri=1; [ "$class" = land ] && pri=0
    seq=$( { flock 8
             n=$(cat "$q/next" 2>/dev/null)
             case "$n" in ''|*[!0-9]*) n=0 ;; esac
             printf '%s\n' "$((n + 1))" >"$q/next"
             printf '%012d' "$n"; } 8>"$q/.mutex" 2>/dev/null )
    [ -n "$seq" ] || { flock -w "$timeout" 9 && return 0; return 5; }
    me="$q/$pri.$seq.${BASHPID:-$$}"
    hone_pid_start "${BASHPID:-$$}" >"$me" 2>/dev/null \
        || { flock -w "$timeout" 9 && return 0; return 5; }
    start=$SECONDS
    local last=""
    while :; do
        head=$(hone_queue_head "$q")
        # A land keeps its place while the queue moves: the head changed, or
        # a live taker holds the lock. Its wait counts only while nothing
        # moves. A suite in front can run longer than the timeout, and a
        # land that timed out rejoined at the back of the queue.
        if [ "$pri" -eq 0 ] && [ "$head" != "$last" ]; then start=$SECONDS; last="$head"; fi
        left=$(( timeout - (SECONDS - start) ))
        if [ "$head" = "$me" ]; then
            [ "$left" -gt 1 ] && left=1
            [ "$left" -lt 0 ] && left=0
            if flock -w "$left" 9; then
                # The pid goes in first: inside $( ) BASHPID names the subshell.
                local mypid="${BASHPID:-$$}"
                printf '%s %s\n' "$mypid" "$(hone_pid_start "$mypid")" \
                    >"$q/holder" 2>/dev/null
                rm -f "$me"; return 0
            fi
        fi
        [ "$pri" -eq 0 ] && hone_queue_holder_live "$q" && start=$SECONDS
        [ $(( SECONDS - start )) -ge "$timeout" ] && { rm -f "$me"; return 5; }
        [ "$head" = "$me" ] || sleep 0.2
    done
}

# ------------------------------------------------------- the gate receipt

# The hash of the tree as it stands in $PWD: HEAD's tree plus every
# uncommitted edit and every untracked file that git does not ignore. A
# copy of the index takes the edits, so the real index never moves. Empty
# on failure.
hone_tree_state() {
    local gd idx tree
    gd=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 0
    idx=$(mktemp "${TMPDIR:-/tmp}/hone-index.XXXXXX" 2>/dev/null) || return 0
    cp "$gd/index" "$idx" 2>/dev/null || rm -f "$idx"
    tree=$(GIT_INDEX_FILE="$idx" git add -A . >/dev/null 2>&1 \
           && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null)
    rm -f "$idx"
    printf '%s' "$tree"
}

# The plugin version, which keys the gate receipt. A gate with new steps
# must not trust a receipt that an older gate wrote.
hone_plugin_version() {
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$(dirname -- "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json" 2>/dev/null | head -1
}

# Exit 0 when HEAD in $PWD carries no commit of its own: a local branch
# outside hone/ (the trunk) already contains it. A hone/* branch that add
# just cut is such a branch. Its tree is the trunk's, and no change exists
# on it yet. Another hone/* branch does not count, so a branch cut from a
# change branch still verifies what it carries.
hone_branch_fresh() {
    git symbolic-ref -q HEAD >/dev/null 2>&1 || return 1
    [ -n "$(git for-each-ref --contains HEAD --format='%(refname)' refs/heads/ 2>/dev/null \
            | grep -v '^refs/heads/hone/')" ]
}

# Write the green receipt of the full suite for the tree in $PWD. $1 = who
# ran it: `gate` (tests, type-check, lint) or `verify` (tests only). The
# line is "<version> <branch> <tree> <who>". A detached HEAD or a fresh
# branch gets no receipt, because no change is there to vouch for.
hone_gate_receipt_write() {
    local branch tree
    branch=$(git symbolic-ref -q --short HEAD 2>/dev/null) || return 0
    hone_branch_fresh && [ -z "$(git status --porcelain 2>/dev/null)" ] && return 0
    tree=$(hone_tree_state)
    [ -n "$tree" ] || return 0
    printf '%s %s %s %s\n' "$(hone_plugin_version)" "$branch" "$tree" "$1" \
        > "$(git rev-parse --git-dir 2>/dev/null)/hone-gate-green" 2>/dev/null || true
    return 0
}

# ---------------------------------------------------------- failure tails

# Print the lines of a suite's output (on stdin) that report a failure, each
# with a little context, at most $1 lines (default 20). Then the last three
# lines, where a runner prints its summary. Output of $1 lines or fewer
# prints whole. With no such line, print the last $1 lines. A plain tail of
# a long run showed only passing tests twice in the field, because the
# runner printed its failures early.
hone_fail_excerpt() {
    awk -v max="${1:-20}" '
        { line[NR] = $0; l = tolower($0)
          if (l ~ /(fail|error|fatal|not ok|✗|✖|panic|traceback|assert)/ \
              && l !~ /^[[:space:]]*(✓|✔|ok |pass)/ \
              && l !~ /(^|[^0-9])0 (fail|error)/) hit[NR] = 1 }
        END {
            if (NR <= max) { for (i = 1; i <= NR; i++) print line[i]; exit }
            for (i = 1; i <= NR; i++) if (hit[i]) for (j = i - 1; j <= i + 2; j++) keep[j] = 1
            c = 0; last = 0
            for (i = 1; i <= NR && c < max; i++) if (keep[i]) {
                if (last && i > last + 1) print "..."
                print line[i]; c++; last = i }
            if (c == 0) { s = NR - max + 1; if (s < 1) s = 1
                          for (i = s; i <= NR; i++) print line[i]; exit }
            s = NR - 2; if (s <= last) s = last + 1
            if (s <= NR) print "..."
            for (i = s; i <= NR; i++) print line[i]
        }'
}

# ------------------------------------------------------- nested sessions

# Exit 0 when this hook runs inside a nested `claude -p "/code-review ..."`
# session, the review that the run skill starts. Such a session reviews a
# diff. It owns no change, so the Stop gate and the nag have nothing to say
# to it. In the field the gate there ran the full suite and held the suite
# lock, and the nag told the reviewer to start a run. The sign is an
# ancestor process whose command line runs claude in print mode on
# /code-review. A hook is a child of its claude process, so the walk is
# short.
hone_nested_review() {
    local pid="$PPID" n=0 ppid args
    while [ "$n" -lt 8 ] && [ "${pid:-0}" -gt 1 ]; do
        read -r ppid args < <(ps -o ppid= -o args= -p "$pid" 2>/dev/null)
        case "$args" in
            *claude*" -p "*/code-review*|*claude*" --print "*/code-review*) return 0 ;;
        esac
        pid="$ppid"; n=$((n + 1))
    done
    return 1
}
