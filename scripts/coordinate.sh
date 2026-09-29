#!/bin/bash
# hone coordinate helper. The mechanical half of watching run sessions under
# herdr: a ticker that reads each watched session's state from herdr, an event
# file that holds what happened, and a wait that hands the next events to the
# session that watches. The watching session (MAIN of `--all` under herdr) keeps
# no watcher of its own. Its context can end, and no event is lost, because the
# events live in a file.
#
# State lives in <git-common-dir>/hone-coordinate/, beside the land lock, so
# every worktree of the repository sees the same state and git never tracks it:
#   sessions/<agent>    one watched session, key=value lines
#   events              one event per line: n, epoch, change, kind, detail
#   ticker.lock         held by the one live ticker
#   wait.<session>.pid  the live wait of a watching session
#   cursor.<session>    the last event that session's wait printed
#
#   coordinate.sh watch <change> <agent> [<tab-id>]
#       Register a herdr agent that runs <change>, and start the ticker. The
#       tab defaults to the agent's own tab. The watching session is the one
#       whose shell runs this (CLAUDE_CODE_SESSION_ID). Needs herdr 0.9.0 or
#       later, whose agent records carry state_change_seq.
#       Exit: 0 watching · 2 usage/not-a-repo/no herdr/herdr too old.
#
#   coordinate.sh unwatch <change>
#       Stop watching <change>, for a stopped session whose tab the person
#       closed or gave up. A land removes its session by itself.
#       Exit: 0 · 2 usage/not-a-repo.
#
#   coordinate.sh wait [--since <n>]
#       Block until an event arrives that this session has not seen, print
#       every such event, and exit 0. Run it in the background and end the
#       turn. The harness wakes the session when it exits. It starts the
#       ticker when none runs. With no watched session and no unseen event it
#       prints so and exits 0 at once. --since <n> reads from event n on,
#       for a caller with no session id.
#       Exit: 0 printed · 2 usage/not-a-repo.
#
#   coordinate.sh list
#       Print each watched session: change, agent, state, and for how long.
#       Exit: 0.
#
#   coordinate.sh events
#       Print the whole event file, oldest first. Exit: 0.
#
#   coordinate.sh ticker
#       The ticker loop. `watch` and `wait` start it in the background, and
#       the watch hook starts it again when it died. Only one runs per
#       repository. Every HONE_COORD_TICK seconds (default 15) it reads each
#       watched agent with `herdr agent get`, and it writes these events:
#         landed      land merged the change (land writes this one itself)
#         stopped     land stopped at exit 6 to 9 (land writes this one too,
#                     and land's own notification told the person)
#         needs-you   the agent sat blocked (a question or an approval) for
#                     30 seconds
#         quiet       the agent sat idle for HONE_COORD_QUIET seconds
#                     (default 600) after it last worked, with no land
#                     since. That is a stop, a report, or a question in text.
#         gone        herdr no longer knows the agent
#       A needs-you or a quiet event also shows a herdr notification that
#       names the repository and the tab, so the person hears of it while the
#       watching session sleeps. A landed or a gone session leaves the watch.
#       The ticker exits when no session is left. Exit: 0.
#
#   coordinate.sh ensure
#       Start the ticker when none runs. The watch hook calls it on each
#       Stop of a watching session. Exit: 0.
#
#   A session that runs its turn in the background can look idle while a
#   background shell works (herdr 0.9 counts that shell as idle). The quiet
#   threshold is long for that reason, and the wait sleeps no longer than that.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../hooks/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../hooks/messages.sh"

HONE_COORD="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/coordinate.sh"
# A blocked agent waits this long before the ticker calls it a need. herdr
# reports a short blocked state while it reads a new screen.
COORD_BLOCKED=30

coord_state_dir() {
    local common
    common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 1
    printf '%s/hone-coordinate' "$common"
}

# The session's key=value file, read into the kv_* variables.
kv_load() {
    kv_change="" kv_agent="" kv_tab="" kv_owner="" kv_registered=0 kv_seq=-1
    kv_status=unknown kv_since=0 kv_worked=0 kv_notified=0
    local k v
    while IFS='=' read -r k v; do
        case "$k" in
            change) kv_change=$v ;; agent) kv_agent=$v ;; tab) kv_tab=$v ;;
            owner) kv_owner=$v ;; registered) kv_registered=$v ;; seq) kv_seq=$v ;;
            status) kv_status=$v ;; since) kv_since=$v ;; worked) kv_worked=$v ;;
            notified) kv_notified=$v ;;
        esac
    done < "$1"
}

kv_save() {
    local tmp="$1.$$"
    printf 'change=%s\nagent=%s\ntab=%s\nowner=%s\nregistered=%s\nseq=%s\nstatus=%s\nsince=%s\nworked=%s\nnotified=%s\n' \
        "$kv_change" "$kv_agent" "$kv_tab" "$kv_owner" "$kv_registered" "$kv_seq" \
        "$kv_status" "$kv_since" "$kv_worked" "$kv_notified" > "$tmp" && mv -f "$tmp" "$1"
}

# One string field of a herdr JSON answer. herdr prints compact JSON, and the
# fields read here occur once in an agent or a tab record.
json_str() { printf '%s' "$1" | sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" | head -1; }
json_num() { printf '%s' "$1" | sed -n "s/.*\"$2\":\([0-9][0-9]*\).*/\1/p" | head -1; }

# herdr, bounded: a server that does not answer must not hang a tick.
herdr_call() {
    if command -v timeout >/dev/null 2>&1; then timeout 10 herdr "$@"; else herdr "$@"; fi
}

# True when event file $1 holds a `$3` event for change $2 at or after epoch $4.
has_event() {
    [ -f "$1" ] || return 1
    awk -F'\t' -v c="$2" -v k="$3" -v t="$4" '$3 == c && $4 == k && $2 >= t { f = 1 } END { exit !f }' "$1"
}

# Start the ticker unless one holds the lock. The ticker takes the lock
# itself, so two callers that race here start at most one live ticker.
coord_ensure_ticker() {
    local dir="$1"
    mkdir -p "$dir" 2>/dev/null || return 0
    if command -v flock >/dev/null 2>&1; then
        flock -n "$dir/ticker.lock" true 2>/dev/null || return 0
    fi
    if command -v setsid >/dev/null 2>&1; then
        setsid -f bash "$HONE_COORD" ticker >/dev/null 2>&1 </dev/null
    else
        nohup bash "$HONE_COORD" ticker >/dev/null 2>&1 </dev/null &
    fi
}

coord_notify() {
    local change="$1" reason="$2" tab="$3" label msg
    [ -n "$tab" ] && label=$(json_str "$(herdr_call tab get "$tab" 2>/dev/null)" label)
    msg=$(msg_coord_notify "$(basename "$PWD")" "$change" "$reason" "${label:-${tab:-unknown}}")
    herdr_call notification show "${msg%%$'\n'*}" --body "${msg#*$'\n'}" \
        --sound request >/dev/null 2>&1 || true
}

# One tick for one watched session. Returns 1 when the session left the watch.
coord_tick_session() {
    local sf="$1" dir="$2" out st sq now
    kv_load "$sf"
    if has_event "$dir/events" "$kv_change" landed "$kv_registered"; then
        rm -f "$sf"; return 1
    fi
    out=$(herdr_call agent get "$kv_agent" 2>&1)
    case "$out" in
        *'"agent_not_found"'*|*'"agent_not_running"'*)
            hone_coord_event "$dir" "$kv_change" gone "agent $kv_agent"
            rm -f "$sf"; return 1 ;;
    esac
    st=$(json_str "$out" agent_status)
    sq=$(json_num "$out" state_change_seq)
    # No answer from the server: keep the session and try on the next tick.
    [ -n "$st" ] && [ -n "$sq" ] || return 0
    now=$(date +%s)
    if [ "$sq" != "$kv_seq" ]; then
        kv_seq=$sq kv_status=$st kv_since=$now kv_notified=0
        [ "$st" = working ] && kv_worked=$now
    fi
    if [ "$kv_notified" = 0 ]; then
        case "$kv_status" in
            blocked)
                if [ $((now - kv_since)) -ge "$COORD_BLOCKED" ]; then
                    hone_coord_event "$dir" "$kv_change" needs-you "a question or an approval prompt"
                    coord_notify "$kv_change" "a question or an approval prompt" "$kv_tab"
                    kv_notified=1
                fi ;;
            idle|done)
                if [ $((now - kv_since)) -ge "${HONE_COORD_QUIET:-600}" ]; then
                    # A land that stopped already told the person.
                    if ! has_event "$dir/events" "$kv_change" stopped "$kv_worked"; then
                        hone_coord_event "$dir" "$kv_change" quiet "idle for $(( (now - kv_since) / 60 )) min"
                        coord_notify "$kv_change" "the session went quiet: a stop, a report, or a question" "$kv_tab"
                    fi
                    kv_notified=1
                fi ;;
        esac
    fi
    kv_save "$sf"
    return 0
}

cmd_ticker() {
    local dir f active
    command -v herdr >/dev/null 2>&1 || return 0
    dir=$(coord_state_dir) || return 0
    mkdir -p "$dir/sessions"
    exec 8>"$dir/ticker.lock"
    flock -n 8 2>/dev/null || return 0
    while :; do
        active=0
        for f in "$dir"/sessions/*; do
            [ -f "$f" ] || continue
            coord_tick_session "$f" "$dir" && active=1
        done
        [ "$active" -eq 1 ] || return 0
        sleep "${HONE_COORD_TICK:-15}"
    done
}

# Compare dotted versions: true when $1 >= $2.
version_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

cmd_watch() {
    local change="${1:-}" agent="${2:-}" tab="${3:-}" dir ver f
    [ -n "$change" ] && [ -n "$agent" ] || { msg_coord_usage >&2; return 2; }
    printf '%s' "$agent" | grep -qE '^[a-z][a-z0-9_-]{0,31}$' || { msg_coord_usage >&2; return 2; }
    command -v herdr >/dev/null 2>&1 || { msg_coord_no_herdr >&2; return 2; }
    ver=$(herdr --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    version_ge "${ver:-0.0.0}" 0.9.0 || { msg_coord_herdr_old "${ver:-unknown}" >&2; return 2; }
    dir=$(coord_state_dir) || { msg_coord_usage >&2; return 2; }
    mkdir -p "$dir/sessions"
    [ -n "$tab" ] || tab=$(json_str "$(herdr_call agent get "$agent" 2>/dev/null)" tab_id)
    f="$dir/sessions/$agent"
    kv_change=$change kv_agent=$agent kv_tab=$tab kv_owner="${CLAUDE_CODE_SESSION_ID:-}"
    kv_registered=$(date +%s) kv_seq=-1 kv_status=unknown kv_since=$kv_registered
    kv_worked=$kv_registered kv_notified=0
    kv_save "$f"
    coord_ensure_ticker "$dir"
    printf 'hone coordinate: watching %s (agent %s, tab %s).\n' "$change" "$agent" "${tab:-unknown}"
}

cmd_unwatch() {
    local change="${1:-}" dir f
    [ -n "$change" ] || { msg_coord_usage >&2; return 2; }
    dir=$(coord_state_dir) || { msg_coord_usage >&2; return 2; }
    for f in "$dir"/sessions/*; do
        [ -f "$f" ] || continue
        kv_load "$f"
        [ "$kv_change" = "$change" ] && rm -f "$f"
    done
    printf 'hone coordinate: no longer watching %s.\n' "$change"
}

# Print events after n=$2 from file $1 in a readable form.
print_events() {
    awk -F'\t' -v from="$2" '$1 > from {
        cmd = "date -d @" $2 " +%H:%M 2>/dev/null"; t = ""; cmd | getline t; close(cmd)
        printf "[%s] %-24s %-10s %s\n", t, $3, $4, $5 }' "$1"
}

# True when a session file in $1 belongs to owner $2 (any, when $2 is empty).
watching_any() {
    local f
    for f in "$1"/sessions/*; do
        [ -f "$f" ] || continue
        [ -z "$2" ] && return 0
        grep -qxF "owner=$2" "$f" && return 0
    done
    return 1
}

cmd_wait() {
    local dir sid="${CLAUDE_CODE_SESSION_ID:-}" since="" key last
    if [ "${1:-}" = --since ]; then
        since="${2:-}"
        case "$since" in ''|*[!0-9]*) msg_coord_usage >&2; return 2 ;; esac
    fi
    case "$sid" in */*|.*) sid="" ;; esac
    dir=$(coord_state_dir) || { msg_coord_usage >&2; return 2; }
    mkdir -p "$dir/sessions"
    key=${sid:-none}
    [ -n "$since" ] || since=$(cat "$dir/cursor.$key" 2>/dev/null || echo 0)
    # A global, because the EXIT trap runs after this function's locals are gone.
    COORD_WAIT_PID="$dir/wait.$key.pid"
    printf '%s\n' "$$" > "$COORD_WAIT_PID"
    trap 'rm -f "$COORD_WAIT_PID"' EXIT
    coord_ensure_ticker "$dir"
    while :; do
        last=$(awk -F'\t' 'END { print $1 + 0 }' "$dir/events" 2>/dev/null || echo 0)
        [ -n "$last" ] || last=0
        if [ "$last" -gt "$since" ]; then
            print_events "$dir/events" "$since"
            [ -n "$sid" ] && printf '%s\n' "$last" > "$dir/cursor.$key"
            return 0
        fi
        if ! watching_any "$dir" "$sid"; then
            printf 'hone coordinate: no session is watched, and no event is new.\n'
            return 0
        fi
        # The ticker may have died with a session still watched.
        coord_ensure_ticker "$dir"
        sleep 2
    done
}

cmd_list() {
    local dir f now
    dir=$(coord_state_dir) || return 0
    now=$(date +%s)
    for f in "$dir"/sessions/*; do
        [ -f "$f" ] || continue
        kv_load "$f"
        printf '%-24s %-24s %-8s %s min\n' "$kv_change" "$kv_agent" "$kv_status" $(( (now - kv_since) / 60 ))
    done
}

cmd_events() {
    local dir
    dir=$(coord_state_dir) || return 0
    [ -f "$dir/events" ] && print_events "$dir/events" 0
    return 0
}

main() {
    local root sub="${1:-}"
    root=$(git rev-parse --show-toplevel 2>/dev/null) || { msg_coord_usage >&2; return 2; }
    # The ticker and the notifications name the repository by the primary
    # tree, whichever worktree the caller stands in.
    root=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel 2>/dev/null || printf '%s' "$root")
    cd "$root" || return 2
    shift || true
    case "$sub" in
        watch)   cmd_watch "$@" ;;
        unwatch) cmd_unwatch "$@" ;;
        wait)    cmd_wait "$@" ;;
        list)    cmd_list "$@" ;;
        events)  cmd_events "$@" ;;
        ticker)  cmd_ticker "$@" ;;
        ensure)  coord_ensure_ticker "$(coord_state_dir)" ;;
        *) msg_coord_usage >&2; return 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
