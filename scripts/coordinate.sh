#!/bin/bash
# hone coordinate helper. The mechanical half of watching run sessions under
# herdr: a ticker that reads each watched session's state from herdr, an event
# file that holds what happened, and a wait that hands the next events to the
# session that watches. The watching session (the coordinator of
# skills/coordinate/SKILL.md) keeps no watcher of its own. Its context can end, and no event is lost, because the
# events live in a file.
#
# State lives in <git-common-dir>/hone-coordinate/, beside the land lock, so
# every worktree of the repository sees the same state and git never tracks it:
#   sessions/<agent>    one watched session, key=value lines, with the
#                       hone version of the coordinator that watches it
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
#   coordinate.sh open
#       Make this herdr tab the repository's coordinator: label it hone, or
#       hone-2, hone-3 when another tab of this workspace holds the label.
#       Then print the board. Exit: 0 · 2 not-a-repo/not in herdr/herdr
#       too old.
#
#   coordinate.sh board [<path>]
#       One line per change, the ones that need the person first: needs
#       you (with the last event), running, in flight elsewhere (with its
#       owner), Plan ready, and landed in the last 24 hours. A <path> keeps
#       the changes whose name or Plan names it. It reads the repository,
#       the event file, and the watched sessions, never a session's report.
#       In shared mode it fetches the claims. Exit: 0.
#
#   coordinate.sh admit <change | garden> [--after-ok <name>]...
#       Say whether <change> may start now, against every change in flight:
#       a worktree here, a session this repository watches, and in shared
#       mode each claim on the remote, whoever holds it. Mechanical refusals
#       exit 4 with the reason: the change is in flight already, garden next
#       to any other change, or a run next to garden. Garden finds its work
#       as it goes, so no Plan can say what it touches. Otherwise it exits 0
#       and prints the candidate's Plan and the Plan of each change in
#       flight, with its owner. The caller then compares them by the
#       checklist in skills/run/references/parallel.md. It needs no herdr.
#       A Plan with an `Owner: <name>` line (the plan skill writes it in
#       shared mode) is admitted only for the developer whose git user.name
#       is <name>, so a coordinator never takes a colleague's Plan.
#       A Plan that orders another change first waits (exit 4) while that
#       change is open: its Plan is still in the primary tree, or it is in
#       flight. admit reads the order from a sentence like "start it only
#       after `a` has landed" or "`a`: run it first". A sentence that
#       says "either order" orders nothing. `--after-ok <name>`, once per
#       name, lifts the hold for that name, when the person says the order
#       does not bind.
#       Exit: 0 compare · 4 wait · 2 usage/not-a-repo.
#
#   coordinate.sh start run <change> [--model <model>] [--after-ok <name>]...
#   coordinate.sh start garden [--model <model>]
#   coordinate.sh start plan "<idea>" [--model <model>]
#   coordinate.sh start consolidate [--model <model>]
#       Open a herdr tab in this workspace, start Claude Code in it, and
#       prompt it once: /hone:run <change>, /hone:garden, /hone:plan
#       <idea>, or the global consolidate pass of parallel.md. The session runs in auto permission mode, on opus unless
#       --model says otherwise. Every session opens in the background and is
#       watched. Every session but a plan first passes the mechanical half of
#       admit. The tab label names the verb and the change: run:<change>,
#       garden, consolidate, or plan:<idea>, where <idea> is the idea's first
#       40 characters in lowercase, with hyphens and slashes, and -2, -3 when
#       a watched plan holds the label. A plan's watch is under that label.
#       The workspace names the repository. The agent name is the label in
#       the form herdr accepts (run-<change>, plan-<idea>), with -2, -3 on a
#       collision.
#       Exit: 0 started · 4 admit refused · 2 usage/not-a-repo/not in
#       herdr/herdr too old/herdr refused a step (the tab stays).
#
#   coordinate.sh planned <slug>
#       The plan skill runs this last, in a plan tab that start opened, once
#       it committed .plans/<slug>.md. It writes a planned event for the
#       watch of this tab (HERDR_TAB_ID), and relabels the tab plan:<slug>.
#       In a tab that no watch names, it says so on stderr and still writes
#       the event, under plan:<slug>, where a coordinator's event file
#       exists. The tab then stays open. Exit: 0 (the Plan is committed, so
#       the plan did not fail) · 2 usage/not-a-repo/.plans/<slug>.md not in
#       HEAD.
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
#       Print each watched session: change, agent, tab ID, state, and for
#       how long.
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
#         finished    a garden or consolidate session went quiet, and for
#                     garden no hone/garden/* worktree is left. Both land
#                     under names of their own, so no landed event ends
#                     their watch.
#         planned     a plan session committed its Plan (planned writes
#                     this one). When the session is next idle, the ticker
#                     closes its tab.
#         updated     a newer hone wrote to the event file than the
#                     coordinator runs (every writer checks, once per
#                     version). The coordinator must restart to load it.
#       A needs-you or a quiet event also shows a herdr notification that
#       names the repository and the tab, so the person hears of it while the
#       watching session sleeps. A landed, gone, finished, or planned session
#       leaves the watch.
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

# worktree.sh has no side effects when sourced. It brings common.sh,
# messages.sh, and the claim and worktree helpers that admit reads.
# shellcheck source=scripts/worktree.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/worktree.sh"

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
    kv_status=unknown kv_since=0 kv_worked=0 kv_notified=0 kv_version=""
    local k v
    while IFS='=' read -r k v; do
        case "$k" in
            change) kv_change=$v ;; agent) kv_agent=$v ;; tab) kv_tab=$v ;;
            owner) kv_owner=$v ;; registered) kv_registered=$v ;; seq) kv_seq=$v ;;
            status) kv_status=$v ;; since) kv_since=$v ;; worked) kv_worked=$v ;;
            notified) kv_notified=$v ;; version) kv_version=$v ;;
        esac
    done < "$1"
}

kv_save() {
    local tmp="$1.$$"
    printf 'change=%s\nagent=%s\ntab=%s\nowner=%s\nregistered=%s\nseq=%s\nstatus=%s\nsince=%s\nworked=%s\nnotified=%s\n' \
        "$kv_change" "$kv_agent" "$kv_tab" "$kv_owner" "$kv_registered" "$kv_seq" \
        "$kv_status" "$kv_since" "$kv_worked" "$kv_notified" > "$tmp" || return 1
    # The coordinator's hone version. A newer writer compares against it.
    [ -z "$kv_version" ] || printf 'version=%s\n' "$kv_version" >> "$tmp"
    mv -f "$tmp" "$1"
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
    # A plan whose Plan is committed is done: close its tab once its turn ends.
    case "$kv_change:$kv_status" in
        plan:*:idle|plan:*:done)
            if has_event "$dir/events" "$kv_change" planned "$kv_registered"; then
                herdr_call tab close "$kv_tab" >/dev/null 2>&1
                rm -f "$sf"; return 1
            fi ;;
    esac
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
                    # Garden and consolidate land under names of their own,
                    # so no landed event ends their watch. Quiet ends it,
                    # unless a garden cut still holds its worktree.
                    if coord_pass_finished "$kv_change"; then
                        hone_coord_event "$dir" "$kv_change" finished "the session went quiet with no worktree of its own"
                        rm -f "$sf"; return 1
                    fi
                fi ;;
        esac
    fi
    kv_save "$sf"
    return 0
}

# True when the pass behind a garden or consolidate watch is over: the
# session went quiet, and for garden no hone/garden/* worktree is left.
coord_pass_finished() {
    case "$1" in
        consolidate) return 0 ;;
        garden)
            ! git -C "$(main_root_of)" worktree list --porcelain 2>/dev/null \
                | grep -q '^branch refs/heads/hone/garden/' ;;
        *) return 1 ;;
    esac
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

# herdr is installed and new enough, or say why not.
herdr_ready() {
    local ver
    command -v herdr >/dev/null 2>&1 || { msg_coord_no_herdr >&2; return 2; }
    ver=$(herdr --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    version_ge "${ver:-0.0.0}" 0.9.0 || { msg_coord_herdr_old "${ver:-unknown}" >&2; return 2; }
}

cmd_watch() {
    local change="${1:-}" agent="${2:-}" tab="${3:-}" dir f
    [ -n "$change" ] && [ -n "$agent" ] || { msg_coord_usage >&2; return 2; }
    printf '%s' "$agent" | grep -qE '^[a-z][a-z0-9_-]{0,31}$' || { msg_coord_usage >&2; return 2; }
    herdr_ready || return 2
    dir=$(coord_state_dir) || { msg_coord_usage >&2; return 2; }
    mkdir -p "$dir/sessions"
    [ -n "$tab" ] || tab=$(json_str "$(herdr_call agent get "$agent" 2>/dev/null)" tab_id)
    f="$dir/sessions/$agent"
    kv_change=$change kv_agent=$agent kv_tab=$tab kv_owner="${CLAUDE_CODE_SESSION_ID:-}"
    kv_registered=$(date +%s) kv_seq=-1 kv_status=unknown kv_since=$kv_registered
    kv_worked=$kv_registered kv_notified=0 kv_version=$(hone_version)
    kv_save "$f"
    coord_ensure_ticker "$dir"
    printf 'hone coordinate: watching %s (agent %s, tab %s).\n' "$change" "$agent" "${tab:-unknown}"
}

# Every change in flight, one per line: change, TAB, owner. A worktree
# here, then a watched session with no worktree yet, then each claim on the
# shared remote that has no worktree here. A remote that does not answer
# adds nothing.
coord_inflight() {
    local main_root="$1" dir="$2" path branch f remote cref subj c seen=""
    while IFS=$'\t' read -r path branch; do
        case "$branch" in hone/*) ;; *) continue ;; esac
        c=${branch#hone/}
        seen+=" $c "
        printf '%s\tthis clone\n' "$c"
    done < <(parse_worktrees "$(git -C "$main_root" worktree list --porcelain 2>/dev/null)" "$main_root")
    for f in "$dir"/sessions/*; do
        [ -f "$f" ] || continue
        c=$(sed -n 's/^change=//p' "$f")
        # A plan session changes no file outside .plans/.
        case "$c" in plan:*) continue ;; esac
        case "$seen" in *" $c "*) continue ;; esac
        seen+=" $c "
        printf '%s\tthis clone, starting\n' "$c"
    done
    remote=$(shared_remote "$main_root")
    [ -n "$remote" ] || return 0
    git -C "$main_root" fetch -q --prune "$remote" '+refs/hone/claim/*:refs/hone/remote-claim/*' >/dev/null 2>&1
    while IFS= read -r cref; do
        [ -n "$cref" ] || continue
        c=${cref#refs/hone/remote-claim/}
        case "$seen" in *" $c "*) continue ;; esac
        subj=$(git -C "$main_root" log -1 --format=%s "$cref" 2>/dev/null)
        # "hone claim: <change> by <name> <<email>> on <host> at <time>"
        subj=$(printf '%s' "$subj" | sed -n 's/^hone claim: .* by \(.*\) <[^>]*> on \([^ ]*\) at .*/\1 on \2/p')
        printf '%s\t%s\n' "$c" "${subj:-another clone}"
    done < <(git -C "$main_root" for-each-ref --format='%(refname)' 'refs/hone/remote-claim/' 2>/dev/null)
}

# The owner a Plan names on its `Owner:` line, or nothing.
coord_plan_owner() {
    coord_plan_text "$1" "$2" | sed -n 's/^Owner:[[:space:]]*//p' | head -1 | sed 's/[[:space:]]*$//'
}

# The Plan of change $2, from the primary tree, else from the shared
# remote's primary branch, which holds a Plan another developer committed.
coord_plan_text() {
    local main_root="$1" c="$2" remote primary
    if [ -f "$main_root/.plans/$c.md" ]; then
        cat "$main_root/.plans/$c.md"; return 0
    fi
    remote=$(shared_remote "$main_root")
    primary=$(git -C "$main_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$remote" ] && git -C "$main_root" show "$remote/$primary:.plans/$c.md" 2>/dev/null; then
        return 0
    fi
    printf '(no Plan for %s here or on the shared remote)\n' "$c"
}

# The changes a Plan's text on stdin orders before it, one per line: each
# backticked name in a sentence of the form "after `a` (and `b`) land(s|ed)"
# or "`a` ...: run it first". A sentence that says "either order" orders
# nothing. The caller keeps only the names that are open changes.
coord_plan_after() {
    # Markdown wraps a sentence over lines. A blank line or a list item
    # starts a new unit, and a unit's lines join into one.
    awk '
        function unit(   l, ns, i, s, ls, seg, rest, lr, q, j) {
            ns = split(buf, sent, /\. /)
            for (i = 1; i <= ns; i++) {
                s = sent[i]; ls = tolower(s); seg = ""
                if (ls ~ /either order/) continue
                if (match(ls, /(^|[^a-z])after /)) {
                    rest = substr(s, RSTART); lr = substr(ls, RSTART); q = 0
                    for (j = 1; j <= length(lr) - 3; j++) if (substr(lr, j, 4) == "land") q = j
                    if (q > 0) seg = substr(rest, 1, q)
                }
                if (match(ls, /(run|land|start) (it|this|that|them) first/)) seg = seg " " substr(s, 1, RSTART)
                while (match(seg, /`[^`]+`/)) {
                    print substr(seg, RSTART + 1, RLENGTH - 2)
                    seg = substr(seg, RSTART + RLENGTH)
                }
            }
            buf = ""
        }
        /^[[:space:]]*$/ { unit(); next }
        /^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]/ { unit() }
        { buf = buf " " $0 }
        END { unit() }'
}

# The open changes that change $2's Plan orders before it, comma-separated:
# a change whose Plan is still in the primary tree, or one in flight ($3).
# A land removes the Plan, so a change with neither has landed.
coord_unlanded_preds() {
    local main_root="$1" change="$2" inflight="$3" p out="" seen=" "
    while IFS= read -r p; do
        case "$p" in "$change"|*[!A-Za-z0-9._/-]*|'') continue ;; esac
        case "$seen" in *" $p "*) continue ;; esac
        seen+="$p "
        if [ -f "$main_root/.plans/$p.md" ] || printf '%s\n' "$inflight" | cut -f1 | grep -qxF -- "$p"; then
            out+="${out:+, }$p"
        fi
    done < <(coord_plan_text "$main_root" "$change" | coord_plan_after)
    printf '%s' "$out"
}

cmd_admit() {
    local change="${1:-}" main_root dir inflight c owner garden_now=0 others="" preds ok=" " p
    [ -n "$change" ] || { msg_coord_usage >&2; return 2; }
    shift
    # --after-ok <name>: the person says this predecessor need not land
    # first. It lifts a false hold of the order parser for that name only.
    while [ $# -gt 0 ]; do
        [ "$1" = --after-ok ] && [ -n "${2:-}" ] || { msg_coord_usage >&2; return 2; }
        ok+="$2 "; shift 2
    done
    main_root=$(main_root_of)
    dir=$(coord_state_dir) || { msg_coord_usage >&2; return 2; }
    inflight=$(coord_inflight "$main_root" "$dir")
    while IFS=$'\t' read -r c owner; do
        [ -n "$c" ] || continue
        if [ "$c" = "$change" ]; then
            msg_coord_admit_inflight "$change" "$owner"; return 4
        fi
        case "$c" in garden|garden/*) garden_now=1 ;; esac
        others+="$c ($owner)"$'\n'
    done <<<"$inflight"
    case "$change" in
        garden|garden/*)
            [ -z "$others" ] || { msg_coord_admit_garden_waits "${others%$'\n'}"; return 4; } ;;
        *)
            owner=$(coord_plan_owner "$main_root" "$change")
            if [ -n "$owner" ] && [ "$owner" != "$(git config user.name 2>/dev/null)" ]; then
                msg_coord_admit_owned "$change" "$owner"; return 4
            fi
            preds=""
            for p in $(coord_unlanded_preds "$main_root" "$change" "$inflight" | tr ',' ' '); do
                case "$ok" in *" $p "*) ;; *) preds+="${preds:+, }$p" ;; esac
            done
            [ -z "$preds" ] || { msg_coord_admit_waits_for "$change" "$preds"; return 4; }
            [ "$garden_now" -eq 0 ] || { msg_coord_admit_waits_for_garden; return 4; } ;;
    esac
    msg_coord_admit_compare "$change" "$(printf '%s' "$inflight" | grep -c .)"
    case "$change" in garden|garden/*) return 0 ;; esac
    printf '\n=== %s (the candidate)\n' "$change"
    coord_plan_text "$main_root" "$change"
    while IFS=$'\t' read -r c owner; do
        [ -n "$c" ] || continue
        printf '\n=== %s (%s)\n' "$c" "$owner"
        coord_plan_text "$main_root" "$c"
    done <<<"$inflight"
    return 0
}

# A herdr agent name for $1-$2: lowercase, [a-z0-9_-] only, 32 characters at
# most, with -2, -3 on a collision with a live agent.
coord_agent_name() {
    local base n i=2
    base=$(printf '%s-%s' "$1" "$2" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g' | cut -c1-32)
    n=$base
    while herdr_call agent get "$n" >/dev/null 2>&1; do
        n="$(printf '%s' "$base" | cut -c1-29)-$i"
        i=$((i + 1))
    done
    printf '%s' "$n"
}

# The watch name of a new plan of slug $2: plan:$2, with -2, -3 when a
# watch in $1 holds it already.
coord_plan_change() {
    local c="plan:$2" i=2
    while grep -qxF "change=$c" "$1"/sessions/* 2>/dev/null; do
        c="plan:$2-$i"; i=$((i + 1))
    done
    printf '%s' "$c"
}

cmd_start() {
    local verb="${1:-}" arg="" model=opus main_root label agent prompt slug
    local out tab pane change dir admitted rc
    local -a after_ok=()
    shift || true
    case "$verb" in
        run|plan) arg="${1:-}"; shift || true; [ -n "$arg" ] || { msg_coord_usage >&2; return 2; } ;;
        garden|consolidate) ;;
        *) msg_coord_usage >&2; return 2 ;;
    esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --model) model="${2:-}"; [ -n "$model" ] || { msg_coord_usage >&2; return 2; } ;;
            --after-ok) [ "$verb" = run ] && [ -n "${2:-}" ] || { msg_coord_usage >&2; return 2; }
                        after_ok+=(--after-ok "$2") ;;
            *) msg_coord_usage >&2; return 2 ;;
        esac
        shift 2
    done
    [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_WORKSPACE_ID:-}" ] || { msg_coord_not_in_herdr >&2; return 2; }
    herdr_ready || return 2
    main_root=$(main_root_of)
    dir=$(coord_state_dir) || { msg_coord_usage >&2; return 2; }
    case "$verb" in
        run)    change=$arg; label="run:$change"; prompt="/hone:run $change"; agent=$(coord_agent_name run "$change") ;;
        garden) change=garden; label=garden; prompt="/hone:garden"; agent=$(coord_agent_name hone garden) ;;
        consolidate)
            change=consolidate; label=consolidate; agent=$(coord_agent_name hone consolidate)
            prompt="Run the global consolidate pass that the hone run skill's references/parallel.md describes: a consolidate-critic over the combined result of the changes that just landed. Land each accepted cut through a worktree change of its own, with the ordinary hone loop. Report when it landed, or that there is nothing to cut." ;;
        plan)   # The idea's first words name the tab: at most 40 of [a-z0-9/-],
                # so a slug like auth/retry stays as run:auth/retry has it.
                slug=$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9/]+#-#g; s#^[-/]+##' \
                    | cut -c1-40 | sed -E 's#[-/]+$##')
                slug=${slug:-$(date +%H%M%S)}
                change=$(coord_plan_change "$dir" "$slug"); label=$change; prompt="/hone:plan $arg"
                agent=$(coord_agent_name plan "$slug") ;;
    esac
    if [ "$verb" != plan ]; then
        admitted=$(cmd_admit "$change" ${after_ok[@]+"${after_ok[@]}"}); rc=$?
        if [ "$rc" -eq 4 ]; then printf '%s\n' "$admitted"; return 4; fi
        [ "$rc" -eq 0 ] || return "$rc"
    fi
    out=$(herdr_call tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$main_root" --label "$label" --no-focus 2>&1)
    tab=$(json_str "$out" tab_id); pane=$(json_str "$out" pane_id)
    [ -n "$tab" ] && [ -n "$pane" ] || { msg_coord_herdr_step "tab create" "$out" >&2; return 2; }
    out=$(herdr agent start "$agent" --kind claude --pane "$pane" -- --permission-mode auto --model "$model" 2>&1) \
        || { msg_coord_herdr_step "agent start" "$out" >&2; return 2; }
    out=$(herdr_call agent prompt "$agent" "$prompt" 2>&1) \
        || { msg_coord_herdr_step "agent prompt" "$out" >&2; return 2; }
    cmd_watch "$change" "$agent" "$tab" >/dev/null
    msg_coord_started "$verb" "$change" "$label" "$agent" "$model"
}

cmd_open() {
    local main_root labels n=1 label=hone
    [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_TAB_ID:-}" ] || { msg_coord_not_in_herdr >&2; return 2; }
    herdr_ready || return 2
    main_root=$(main_root_of)
    # One tab object per line. The label of every other tab in the workspace.
    labels=$(herdr_call tab list --workspace "${HERDR_WORKSPACE_ID:-}" 2>/dev/null | sed 's/},{/}\n{/g' \
        | while IFS= read -r t; do
              [ "$(json_str "$t" tab_id)" = "$HERDR_TAB_ID" ] || json_str "$t" label
              printf '\n'
          done)
    while printf '%s\n' "$labels" | grep -qxF "$label"; do
        n=$((n + 1)); label="hone-$n"
    done
    herdr_call tab rename "$HERDR_TAB_ID" "$label" >/dev/null 2>&1
    printf 'hone coordinate: this tab is %s, the coordinator of %s.\n\n' "$label" "$(basename "$main_root")"
    cmd_board
}

# The Plans in .plans/, one change per line. A Markdown file under the
# directory of another Plan is that Plan's reference, not a Plan.
coord_ready_plans() {
    local main_root="$1" f c d skip
    while IFS= read -r f; do
        c=${f#"$main_root/.plans/"}; c=${c%.md}
        skip=0; d=$c
        while [ "$d" != "${d%/*}" ]; do
            d=${d%/*}
            [ -f "$main_root/.plans/$d.md" ] && skip=1
        done
        [ "$skip" -eq 0 ] && printf '%s\n' "$c"
    done < <(find "$main_root/.plans" -name '*.md' -type f 2>/dev/null | sort)
}

cmd_board() {
    local filter="${1:-}" main_root dir now inflight f c owner ev kind detail when
    local rows="" seen=" " need=0 run=0 ready=0 label
    main_root=$(main_root_of)
    dir=$(coord_state_dir) || return 0
    now=$(date +%s)
    # One row: rank TAB change TAB state TAB owner. Rank 1 needs the person,
    # 2 runs here, 4 is a ready Plan. A <path> filter drops a row before it
    # counts, so the header counts what the board shows.
    row() {
        seen+="$2 "
        if [ -n "$filter" ]; then
            case "$2" in *"$filter"*) ;; *)
                grep -qF -- "$filter" "$main_root/.plans/$2.md" 2>/dev/null || return 0 ;;
            esac
        fi
        rows+="$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\n'
        case "$1" in 1) need=$((need + 1)) ;; 2) run=$((run + 1)) ;; 4) ready=$((ready + 1)) ;; esac
    }
    for f in "$dir"/sessions/*; do
        [ -f "$f" ] || continue
        kv_load "$f"
        ev=$(awk -F'\t' -v c="$kv_change" '$3 == c { k = $4; d = $5; t = $2 } END { if (k != "") print k "\t" t "\t" d }' "$dir/events" 2>/dev/null)
        IFS=$'\t' read -r kind when detail <<<"$ev"
        label=$(json_str "$(herdr_call tab get "$kv_tab" 2>/dev/null)" label)
        label=${label:-$kv_tab}
        # A land that stopped needs the person at once. The ticker waits for
        # the quiet threshold only before it calls an idle session a need.
        if [ "$kind" = stopped ] && [ "${when:-0}" -ge "$kv_worked" ]; then
            row 1 "$kv_change" "NEEDS YOU: land stopped, $detail, tab $label" "this clone"
        elif [ "$kv_notified" = 1 ] && [ "$kind" = needs-you ]; then
            row 1 "$kv_change" "NEEDS YOU: $detail, tab $label" "this clone"
        elif [ "$kv_notified" = 1 ] && [ -n "$ev" ]; then
            row 1 "$kv_change" "NEEDS YOU: the session went quiet, tab $label" "this clone"
        else
            row 2 "$kv_change" "running ($kv_status), tab $label" "this clone"
        fi
    done
    inflight=$(coord_inflight "$main_root" "$dir")
    while IFS=$'\t' read -r c owner; do
        [ -n "$c" ] || continue
        case "$seen" in *" $c "*) continue ;; esac
        row 3 "$c" "in flight" "$owner"
    done <<<"$inflight"
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        case "$seen" in *" $c "*) continue ;; esac
        row 4 "$c" "Plan ready" "$(coord_plan_owner "$main_root" "$c")"
    done < <(coord_ready_plans "$main_root")
    if [ -f "$dir/events" ]; then
        while IFS=$'\t' read -r _ c detail; do
            case "$seen" in *" $c "*) continue ;; esac
            row 5 "$c" "landed $detail" ""
        done < <(awk -F'\t' -v t=$((now - 86400)) '$4 == "landed" && $2 >= t { print $2 "\t" $3 "\t" $5 }' "$dir/events")
    fi
    printf '%s · %s running · %s need you · %s ready\n' "$(basename "$main_root")" "$run" "$need" "$ready"
    [ -n "$rows" ] || { printf 'nothing in flight, and no Plan is ready.\n'; return 0; }
    printf '%s' "$rows" | sort -t$'\t' -k1,1n -k2,2 | while IFS=$'\t' read -r _ c detail owner; do
        printf '%-24s %-58s %s\n' "$c" "$detail" "$owner"
    done
}

cmd_planned() {
    local slug="${1:-}" dir f
    [ -n "$slug" ] || { msg_coord_usage >&2; return 2; }
    dir=$(coord_state_dir) || { msg_coord_usage >&2; return 2; }
    git -C "$(main_root_of)" cat-file -e "HEAD:.plans/$slug.md" 2>/dev/null \
        || { msg_coord_plan_uncommitted "$slug" >&2; return 2; }
    for f in "$dir"/sessions/*; do
        [ -n "${HERDR_TAB_ID:-}" ] && [ -f "$f" ] || continue
        kv_load "$f"
        case "$kv_change" in plan:*) ;; *) continue ;; esac
        [ "$kv_tab" = "$HERDR_TAB_ID" ] || continue
        hone_coord_event "$dir" "$kv_change" planned "$slug"
        herdr_call tab rename "$kv_tab" "plan:$slug" >/dev/null 2>&1
        printf 'hone coordinate: %s is planned. This tab closes when the turn ends.\n' "$slug"
        return 0
    done
    # No watch names this tab: a coordinator on an older hone starts plan
    # tabs with no watch. The event still goes to its event file, so its
    # wait prints it. The Plan is committed, so this is no failure: exit 0.
    if [ -d "$dir" ]; then
        hone_coord_event "$dir" "plan:$slug" planned "$slug"
        msg_coord_planned_unwatched "$slug" >&2
    else
        msg_coord_planned_no_coordinator "$slug" >&2
    fi
    return 0
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
        printf '%-24s %-24s %-10s %-8s %s min\n' "$kv_change" "$kv_agent" "$kv_tab" "$kv_status" $(( (now - kv_since) / 60 ))
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
        open)    cmd_open "$@" ;;
        board)   cmd_board "$@" ;;
        admit)   cmd_admit "$@" ;;
        start)   cmd_start "$@" ;;
        watch)   cmd_watch "$@" ;;
        planned) cmd_planned "$@" ;;
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
