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
#   derived/<agent>     the events the ticker derived for one watch
#   ticker.lock         held by the one live ticker
#   wait.<session>.pid  the live wait of a watching session
#   cursor.<session>    the last event that session's wait printed
#   batch-base          the primary branch tip at the batch's first run start
#   consolidated        the last event number when the last consolidate started
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
#       does not bind. A run also waits (exit 4) while HONE_COORD_MAX_RUNS
#       runs are watched already (default 4, 0 turns the cap off). Every
#       watch but a plan counts, because all runs share one suite lock.
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
#       The first run start of a batch records the primary branch tip in
#       batch-base. start consolidate names that base commit and the count of
#       merges since it in the prompt, and asks for cuts named
#       consolidate/<slug>. With no recorded base, the base is the first
#       parent of the oldest merge that a landed event names since the last
#       pass. With neither, it exits 2. Its start ends the batch.
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
#       ticker when none runs. After the events it prints one line with each
#       watched session's last progress line (its own claim), and queues that
#       line for the progress hook of this session, so the person sees it in
#       the coordinator tab. With no watched session and no unseen event it
#       prints so and exits 0 at once. --since <n> reads from event n on,
#       for a caller with no session id. With no event for HONE_COORD_WAIT
#       seconds (default 540), it says so and exits 3, before the harness
#       limit on a background command kills it. The caller starts it again.
#       Exit: 0 printed · 3 ended on time, no event · 2 usage/not-a-repo.
#
#   coordinate.sh send <change | tab-id | agent> <text>
#       The one path from the coordinator to a watched session. It types
#       <text> into the session's herdr pane with `herdr pane run`, and
#       writes a sent event, which the sender's own wait skips. It refuses
#       text that starts with `!`, after any blank: a shell command for the
#       person is the person's to type. It refuses a session that herdr
#       reports blocked, because a question or a prompt there belongs to
#       the person.
#       Exit: 0 sent · 4 refused · 2 usage/not-a-repo/no watch/herdr failed.
#
#   coordinate.sh list
#       Print each watched session: change, agent, tab ID, state, and for
#       how long. For a run, also its sign-off (.hone-proof/<change>: none,
#       names the tip, carries to the tip, or names another commit, by
#       land's own test) and whether a grant (.hone-grant/<change>) exists.
#       The board shows the same for a run that has either, or that stopped
#       at exit 7 or 8.
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
#         landed      land merged the change (land writes this one itself).
#                     The ticker derives it too, from a merge of
#                     hone/<change> on the primary branch that is 60 seconds
#                     old, and names that merge.
#         stopped     land stopped at exit 6 to 9 (land writes this one too,
#                     and land's own notification told the person)
#         needs-you   the agent sat blocked (a question or an approval) for
#                     30 seconds
#         quiet       the agent sat idle for HONE_COORD_QUIET seconds
#                     (default 600) after it last worked, with no land
#                     since. That is a stop, a report, or a question in text.
#         gone        herdr no longer knows the agent
#         turn-ended  the session's turn ended, with the last line of its
#                     message (the watch hook writes this one, in the
#                     session). After it, the ticker writes no quiet event
#                     and shows no notification until the session works again.
#         sent        the coordinator sent the session text (send)
#         finished    a garden or consolidate session went quiet, and no
#                     worktree of its cuts is left (hone/garden/* or
#                     hone/consolidate/*). Both land
#                     under names of their own, so no landed event ends
#                     their watch. When a cut of the pass has merged, an
#                     idle session ends it at once, with no quiet wait.
#         planned     a plan session committed its Plan (planned writes
#                     this one). When the session is next idle, the ticker
#                     closes its tab. The ticker derives it too, for a
#                     .plans/<slug>.md added on the primary branch since a
#                     plan watch began, under plan:<slug>.
#         signed      after a stop at exit 7 or 8, a sign-off appeared at
#         granted     .hone-proof/<change>, or a grant at .hone-grant/<change>
#                     (derived). signed says whether it names the tip.
#         updated     a newer hone wrote to the event file than the
#                     coordinator runs (every writer checks, once per
#                     version). The coordinator must restart to load it.
#       A needs-you or a quiet event also shows a herdr notification that
#       names the repository and the tab, so the person hears of it while the
#       watching session sleeps. A landed, gone, finished, or planned session
#       leaves the watch. A derived event fires once per watch (the state
#       file derived/<agent>), and never after the same event from a session.
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
    # The state that git and the files show, for an event a session missed.
    coord_reconcile "$sf" "$dir" || return 1
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
            if has_event "$dir/events" "$kv_change" planned "$kv_registered" \
               || [ -n "$(coord_derived_get "$dir" "$sf" planned)" ]; then
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
                    # A turn-ended event already woke the coordinator.
                    if ! has_event "$dir/events" "$kv_change" stopped "$kv_worked" \
                        && ! has_event "$dir/events" "$kv_change" turn-ended "$kv_worked"; then
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
# session went quiet, and no worktree of its cuts is left (hone/garden/* or
# hone/consolidate/*). A cut that stopped at land keeps its worktree, so the
# pass is not over while it waits for the person.
coord_pass_finished() {
    case "$1" in
        consolidate|garden)
            ! git -C "$(main_root_of)" worktree list --porcelain 2>/dev/null \
                | grep -q "^branch refs/heads/hone/$1/" ;;
        *) return 1 ;;
    esac
}

# ---- reconcile: the state that git and the files show ----------------------
# A session writes most events, and a missed one left the coordinator blind.
# So each tick also derives planned, landed, signed, granted, and finished
# from the repository. An event fires once: the file derived/<agent> holds
# what the ticker derived for one watch, and an event that a session wrote
# already is not derived again.

# The ticker derives landed only from a merge this many seconds old, so
# land's own landed event comes first.
COORD_LAND_GRACE=60

# Value $3 of the derived file of session file $2 in state dir $1. A file of
# an earlier watch of the same agent name counts as empty.
coord_derived_get() {
    local df="$1/derived/${2##*/}" reg
    reg=$(sed -n 's/^registered=//p' "$2" 2>/dev/null)
    [ "$(sed -n 's/^registered=//p' "$df" 2>/dev/null)" = "$reg" ] || return 0
    sed -n "s/^$3=//p" "$df" 2>/dev/null | tail -1
}

coord_derived_set() {
    local df="$1/derived/${2##*/}" reg
    reg=$(sed -n 's/^registered=//p' "$2" 2>/dev/null)
    mkdir -p "$1/derived" 2>/dev/null || return 0
    [ "$(sed -n 's/^registered=//p' "$df" 2>/dev/null)" = "$reg" ] || printf 'registered=%s\n' "$reg" > "$df"
    { grep -v "^$3=" "$df"; printf '%s=%s\n' "$3" "$4"; } > "$df.$$" 2>/dev/null && mv -f "$df.$$" "$df"
}

# True when event file $1 holds a planned event for Plan slug $2 at or after epoch $3.
coord_planned_seen() {
    awk -F'\t' -v s="$2" -v t="${3:-0}" '$4 == "planned" && $5 == s && $2 >= t { f = 1 } END { exit !f }' "$1" 2>/dev/null
}

# The short SHA and the commit time of the newest merge of branch $2 on the
# primary branch's first parents since epoch $3. A branch that ends in / is a
# prefix: hone/consolidate/ matches every cut. Land writes the subject
# "Merge branch 'hone/<change>'".
coord_merge_since() {
    local pat="Merge branch '$2"
    case "$2" in */) ;; *) pat+="'" ;; esac
    git -C "$1" log --first-parent --merges --since="@$3" -F --grep="$pat" \
        --format='%h %ct' -n 1 HEAD 2>/dev/null
}

# Each Plan committed on the primary branch since epoch $2 that no planned
# event names gets one. The watch whose label slug is the Plan's slug owns
# it, and the ticker closes that tab. A planner that chose another slug
# leaves it under plan:<slug>, so the coordinator still hears of the Plan.
coord_reconcile_plans() {
    local dir="$1" since="$2" main_root p slug d skip
    main_root=$(main_root_of)
    while IFS= read -r p; do
        case "$p" in .plans/*.md) ;; *) continue ;; esac
        slug=${p#.plans/}; slug=${slug%.md}
        # A file under the directory of another Plan is its reference.
        skip=0; d=$slug
        while [ "$d" != "${d%/*}" ]; do
            d=${d%/*}
            git -C "$main_root" cat-file -e "HEAD:.plans/$d.md" 2>/dev/null && skip=1
        done
        [ "$skip" -eq 0 ] || continue
        coord_planned_seen "$dir/events" "$slug" "$since" && continue
        hone_coord_event "$dir" "plan:$slug" planned "$slug"
    done < <(git -C "$main_root" log --first-parent --since="@$since" --diff-filter=A \
                 --name-only --format= HEAD -- .plans 2>/dev/null | sort -u)
}

# Derive what the repository shows for watched session $1 (kv_* loaded).
# Returns 1 when the session left the watch.
coord_reconcile() {
    local sf="$1" dir="$2" main_root m now stop detail kind rec f sum t
    main_root=$(main_root_of)
    now=$(date +%s)
    case "$kv_change" in
        plan:*)
            coord_reconcile_plans "$dir" "$kv_registered" ;;
        garden|consolidate)
            # A pass whose cuts landed, with no worktree left, ends when its
            # turn ends. With no cut landed, the quiet threshold ends it.
            case "$kv_status" in idle|done) ;; *) return 0 ;; esac
            [ $((now - kv_since)) -ge "$COORD_BLOCKED" ] || return 0
            has_event "$dir/events" "$kv_change" finished "$kv_registered" && return 0
            [ -n "$(coord_merge_since "$main_root" "hone/$kv_change/" "$kv_registered")" ] || return 0
            coord_pass_finished "$kv_change" || return 0
            hone_coord_event "$dir" "$kv_change" finished "its cuts landed, and no worktree of them is left"
            rm -f "$sf"; return 1 ;;
        *)
            if ! has_event "$dir/events" "$kv_change" landed "$kv_registered"; then
                m=$(coord_merge_since "$main_root" "hone/$kv_change" "$kv_registered")
                # land retires the branch after a reinstall that can take
                # minutes, and writes its event after that. Wait for both.
                if [ -n "$m" ] && [ $((now - ${m#* })) -ge "$COORD_LAND_GRACE" ] \
                   && { ! git -C "$main_root" rev-parse -q --verify "refs/heads/hone/$kv_change" >/dev/null 2>&1 \
                        || [ $((now - ${m#* })) -ge 600 ]; }; then
                    hone_coord_event "$dir" "$kv_change" landed "${m%% *}"
                    return 0
                fi
            fi
            # After a stop at a person gate, the person's record in the
            # primary tree. A record from before the stop is the one the
            # stop refused.
            stop=$(awk -F'\t' -v c="$kv_change" -v t="$kv_registered" \
                '$3 == c && $4 == "stopped" && $2 >= t { s = $2; d = $5 } END { if (s != "") print s "\t" d }' \
                "$dir/events" 2>/dev/null)
            IFS=$'\t' read -r t detail <<<"$stop"
            case "$detail" in "exit 7"*|"exit 8"*) ;; *) return 0 ;; esac
            for rec in signed:.hone-proof granted:.hone-grant; do
                kind=${rec%%:*}; f="$main_root/${rec#*:}/$kv_change"
                [ -f "$f" ] || continue
                [ "$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)" -ge "$t" ] || continue
                sum=$(cksum < "$f" | cut -d' ' -f1)
                [ "$(coord_derived_get "$dir" "$sf" "$kind")" = "$sum" ] && continue
                coord_derived_set "$dir" "$sf" "$kind" "$sum"
                has_event "$dir/events" "$kv_change" "$kind" "$t" && continue
                if [ "$kind" = signed ]; then
                    hone_coord_event "$dir" "$kv_change" signed "$(coord_signoff_state "$main_root" "$kv_change")"
                else
                    hone_coord_event "$dir" "$kv_change" granted "the person's grant is in the primary tree"
                fi
            done ;;
    esac
    return 0
}

# The person's sign-off of change $2 in primary tree $1, in words. land's
# own test decides whether it names the tip or carries to it.
coord_signoff_state() {
    local root="$1" c="$2" f="$1/.hone-proof/$2" tip base carried
    tip=$(git -C "$root" rev-parse -q --verify "refs/heads/hone/$c^{commit}" 2>/dev/null)
    if [ ! -f "$f" ]; then
        printf 'no sign-off'
    elif [ -z "$tip" ]; then
        printf 'a sign-off, and no branch hone/%s' "$c"
    elif [ -n "$(land_proof_signoff_names_tip "$f" "$tip")" ]; then
        printf 'sign-off names the tip %s' "${tip:0:7}"
    else
        base=$(git -C "$root" merge-base HEAD "$tip" 2>/dev/null)
        carried=$(land_proof_signoff_carries "$root" "$f" "$base" "$tip")
        if [ -n "$carried" ]; then
            printf 'sign-off carries from %s to the tip %s' "${carried:0:7}" "${tip:0:7}"
        else
            printf 'sign-off names another commit, not the tip %s' "${tip:0:7}"
        fi
    fi
}

# Both of the person's records of change $2, for the board and the list.
coord_person_state() {
    local g="no grant"
    [ -f "$1/.hone-grant/$2" ] && g="grant recorded"
    printf '%s, %s' "$(coord_signoff_state "$1" "$2")" "$g"
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

# The count of runs watched in state dir $1: every watch but a plan.
coord_runs_watched() {
    local f n=0
    for f in "$1"/sessions/*; do
        [ -f "$f" ] || continue
        grep -q '^change=plan:' "$f" || n=$((n + 1))
    done
    printf '%s' "$n"
}

cmd_admit() {
    local change="${1:-}" main_root dir inflight c owner garden_now=0 others="" preds ok=" " p max n
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
            [ "$garden_now" -eq 0 ] || { msg_coord_admit_waits_for_garden; return 4; }
            # Every run here shares one suite lock. Past the cap, a land
            # waited on the lock for hours.
            max=${HONE_COORD_MAX_RUNS:-4}
            case "$max" in ''|*[!0-9]*) max=4 ;; esac
            n=$(coord_runs_watched "$dir")
            [ "$max" -eq 0 ] || [ "$n" -lt "$max" ] || { msg_coord_admit_cap "$change" "$n" "$max"; return 4; } ;;
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
    local out tab pane change dir admitted rc base primary short merges
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
            base=$(coord_batch_base "$main_root" "$dir")
            [ -n "$base" ] || { msg_coord_consolidate_no_base >&2; return 2; }
            primary=$(git -C "$main_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
            short=$(git -C "$main_root" rev-parse --short "$base")
            merges=$(git -C "$main_root" rev-list --count --first-parent --merges "$base..HEAD" 2>/dev/null)
            prompt="Run the global consolidate pass that the hone run skill's references/parallel.md describes: a consolidate-critic over the combined result of the changes that just landed. The batch's base commit is $short. Cover all ${merges:-0} merges that \`git log --first-parent --merges --oneline $short..$primary\` lists, not only the latest. Land each accepted cut through a worktree change of its own, named consolidate/<slug>, with the ordinary hone loop. Report when it landed, or that there is nothing to cut." ;;
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
    # The first run of a batch records the primary branch tip, the base
    # that the global consolidate pass reviews from. Its start ends the batch.
    case "$verb" in
        run) [ -s "$dir/batch-base" ] || git -C "$main_root" rev-parse HEAD > "$dir/batch-base" 2>/dev/null ;;
        consolidate) rm -f "$dir/batch-base"
                     awk -F'\t' 'END { print $1 + 0 }' "$dir/events" > "$dir/consolidated" 2>/dev/null ;;
    esac
    msg_coord_started "$verb" "$change" "$label" "$agent" "$model"
}

# The base commit of the global consolidate pass, in full: the primary
# branch tip that the batch's first run start recorded. With none, the first
# parent of the oldest merge that a landed event names since the last pass.
# Nothing when neither is known.
coord_batch_base() {
    local main_root="$1" dir="$2" from sha parents="" b
    b=$(cat "$dir/batch-base" 2>/dev/null)
    if [ -n "$b" ] && git -C "$main_root" cat-file -e "$b^{commit}" 2>/dev/null; then
        printf '%s' "$b"; return 0
    fi
    from=$(cat "$dir/consolidated" 2>/dev/null); from=${from:-0}
    while IFS= read -r sha; do
        b=$(git -C "$main_root" rev-parse -q --verify "$sha^1" 2>/dev/null) && parents+=" $b"
    done < <(awk -F'\t' -v n="$from" '$1 > n && $4 == "landed" { print $5 }' "$dir/events" 2>/dev/null)
    [ -n "$parents" ] || return 0
    # shellcheck disable=SC2086
    git -C "$main_root" merge-base --octopus $parents 2>/dev/null
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
        # The person's own records answer nothing the session asked.
        ev=$(awk -F'\t' -v c="$kv_change" '$3 == c && $4 != "signed" && $4 != "granted" { k = $4; d = $5; t = $2 } END { if (k != "") print k "\t" t "\t" d }' "$dir/events" 2>/dev/null)
        IFS=$'\t' read -r kind when detail <<<"$ev"
        label=$(json_str "$(herdr_call tab get "$kv_tab" 2>/dev/null)" label)
        label="${label:-$kv_tab}"
        # The sign-off and the grant, read from the primary tree, so no one
        # guesses them: when either exists, or a land stopped at a person gate.
        case "$kv_change" in plan:*|garden|consolidate) ;; *)
            if [ -f "$main_root/.hone-proof/$kv_change" ] || [ -f "$main_root/.hone-grant/$kv_change" ] \
               || { [ "$kind" = stopped ] && case "$detail" in "exit 7"*|"exit 8"*) true ;; *) false ;; esac; }; then
                label+=", $(coord_person_state "$main_root" "$kv_change")"
            fi ;;
        esac
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
        # The ticker may have derived the event already. Then this tab
        # only learns that it is done, and the coordinator hears once.
        if coord_planned_seen "$dir/events" "$slug" "$kv_registered"; then
            coord_derived_set "$dir" "$f" planned "$slug"
        else
            hone_coord_event "$dir" "$kv_change" planned "$slug"
        fi
        herdr_call tab rename "$kv_tab" "plan:$slug" >/dev/null 2>&1
        printf 'hone coordinate: %s is planned. This tab closes when the turn ends.\n' "$slug"
        return 0
    done
    # No watch names this tab: a coordinator on an older hone starts plan
    # tabs with no watch. The event still goes to its event file, so its
    # wait prints it. The Plan is committed, so this is no failure: exit 0.
    if [ -d "$dir" ]; then
        coord_planned_seen "$dir/events" "$slug" "$(( $(date +%s) - 86400 ))" || hone_coord_event "$dir" "plan:$slug" planned "$slug"
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
    local dir sid="${CLAUDE_CODE_SESSION_ID:-}" since="" key last end
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
    end=$(( $(date +%s) + ${HONE_COORD_WAIT:-540} ))
    while :; do
        last=$(awk -F'\t' 'END { print $1 + 0 }' "$dir/events" 2>/dev/null || echo 0)
        [ -n "$last" ] || last=0
        if [ "$last" -gt "$since" ]; then
            print_events "$dir/events" "$since"
            coord_progress_board "$dir" "$sid"
            [ -n "$sid" ] && printf '%s\n' "$last" > "$dir/cursor.$key"
            return 0
        fi
        if ! watching_any "$dir" "$sid"; then
            printf 'hone coordinate: no session is watched, and no event is new.\n'
            return 0
        fi
        # The harness kills a background command at its time limit, and
        # then nothing wakes the session. End first, and say so.
        if [ "$(date +%s)" -ge "$end" ]; then
            msg_coord_wait_on_time "${HONE_COORD_WAIT:-540}"
            return 3
        fi
        # The ticker may have died with a session still watched.
        coord_ensure_ticker "$dir"
        sleep 2
    done
}

# The step a progress line stands at, with its mark and note: the last
# segment of its chain that carries a mark. "◆ [c] worktree ✓ > verify … >
# land" gives "verify …".
coord_progress_step() {
    printf '%s' "${1#*] }" | awk -F' > ' '{ for (i = 1; i <= NF; i++) if ($i ~ / /) s = $i; print s }'
}

# One line of every watched session, as its own progress line reports it,
# after a wait printed events. The progress lines are each run's claim, and
# the line says so. A session with no line shows its herdr state. The line
# goes to stdout, and to the queue of the watching session $2, so the
# progress hook shows it to the person in the coordinator tab.
coord_progress_board() {
    local dir="$1" sid="$2" prog f items="" line best bt t c
    prog="${dir%/hone-coordinate}/hone-progress"
    for f in "$dir"/sessions/*; do
        [ -f "$f" ] || continue
        kv_load "$f"
        [ -z "$sid" ] || [ "$kv_owner" = "$sid" ] || continue
        best="" bt=0
        for line in "$prog"/*.last; do
            [ -f "$line" ] || continue
            case "$(head -c 300 "$line")" in
                "◆ [$kv_change] "*|"◆ [$kv_change/"*) ;;
                *) continue ;;
            esac
            t=$(stat -c %Y "$line" 2>/dev/null || echo 0)
            [ "$t" -ge "$bt" ] && { bt=$t; best=$line; }
        done
        if [ -n "$best" ]; then
            line=$(head -1 "$best"); c=${line#◆ [}; c=${c%%]*}
            items+="$c $(coord_progress_step "$line")"$'\n'
        else
            items+="$kv_change ($kv_status)"$'\n'
        fi
    done
    [ -n "$items" ] || return 0
    line=$(msg_coord_progress "$(printf '%s' "$items" | sort | paste -sd'\t' | sed 's/\t/ · /g')")
    printf '%s\n' "$line"
    case "$sid" in ""|*/*|.*) return 0 ;; esac
    { mkdir -p "$prog" && printf '%s\n' "$line" >> "$prog/$sid"; } 2>/dev/null
    return 0
}

cmd_list() {
    local dir f now main_root ps
    dir=$(coord_state_dir) || return 0
    main_root=$(main_root_of)
    now=$(date +%s)
    for f in "$dir"/sessions/*; do
        [ -f "$f" ] || continue
        kv_load "$f"
        # A run's sign-off and grant, as land would read them.
        ps=""
        case "$kv_change" in plan:*|garden|consolidate) ;; *)
            ps="  $(coord_person_state "$main_root" "$kv_change")" ;;
        esac
        printf '%-24s %-24s %-10s %-8s %s min%s\n' "$kv_change" "$kv_agent" "$kv_tab" "$kv_status" \
            $(( (now - kv_since) / 60 )) "$ps"
    done
}

cmd_send() {
    local target="${1:-}" text="${2:-}" dir f out pane st last cur sid="${CLAUDE_CODE_SESSION_ID:-}"
    [ -n "$target" ] && [ -n "$text" ] && [ $# -eq 2 ] || { msg_coord_usage >&2; return 2; }
    # Claude Code runs input that starts with ! as a shell command. Leading
    # blanks made such a relay arrive as text, so both are refused.
    if printf '%s' "$text" | head -1 | grep -qE '^[[:space:]]*!'; then
        msg_coord_send_bang "$target"; return 4
    fi
    dir=$(coord_state_dir) || { msg_coord_usage >&2; return 2; }
    for f in "$dir"/sessions/*; do
        [ -f "$f" ] || continue
        kv_load "$f"
        [ "$kv_change" = "$target" ] || [ "$kv_tab" = "$target" ] || [ "$kv_agent" = "$target" ] || continue
        out=$(herdr_call agent get "$kv_agent" 2>&1)
        pane=$(json_str "$out" pane_id); st=$(json_str "$out" agent_status)
        [ -n "$pane" ] || { msg_coord_herdr_step "agent get" "$out" >&2; return 2; }
        [ "$st" != blocked ] || { msg_coord_send_blocked "$kv_change" "$kv_tab"; return 4; }
        out=$(herdr_call pane run "$pane" "$text" 2>&1) || { msg_coord_herdr_step "pane run" "$out" >&2; return 2; }
        # The sender's own event must not wake its wait: move its cursor
        # past the event when nothing else came between.
        last=$(awk -F'\t' 'END { print $1 + 0 }' "$dir/events" 2>/dev/null); last=${last:-0}
        hone_coord_event "$dir" "$kv_change" sent "$text"
        case "$sid" in ""|*/*|.*) ;; *)
            cur=$(cat "$dir/cursor.$sid" 2>/dev/null)
            if [ "$cur" = "$last" ] && awk -F'\t' -v n=$((last + 1)) -v c="$kv_change" \
                'END { exit !($1 == n && $3 == c && $4 == "sent") }' "$dir/events" 2>/dev/null; then
                printf '%s\n' "$((last + 1))" > "$dir/cursor.$sid"
            fi ;;
        esac
        printf 'hone coordinate: sent to %s (tab %s): %s\n' "$kv_change" "$kv_tab" "$text"
        return 0
    done
    msg_coord_send_unwatched "$target" >&2
    return 2
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
        send)    cmd_send "$@" ;;
        ticker)  cmd_ticker "$@" ;;
        ensure)  coord_ensure_ticker "$(coord_state_dir)" ;;
        *) msg_coord_usage >&2; return 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
