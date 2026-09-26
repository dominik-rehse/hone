#!/bin/bash
# PreToolUse, PostToolUse, and PostToolUseFailure guard for Bash commands
# (Claude Code). It closes the one hole the other two guards cannot see.
#
# guard.sh reads a file path, so it only fires when a FILE TOOL produces one.
# bash-guard.sh reads the command text, so it only fires when the command SPELLS
# OUT both a write construct and a protected path. A tool that writes its own
# files satisfies neither. `bun add` rewrites package.json from inside its own
# process, so no write construct and no path ever appear in the command. Rule 1
# of guard.sh, the primary-tree rule, therefore missed every such write.
#
# This hook checks the EFFECT instead of the command. In the primary tree it
# records the dirty durable paths before the command (PreToolUse) and compares
# them after it (PostToolUse). A command that exits nonzero fires
# PostToolUseFailure instead, and a failed command can still write, so the
# comparison runs on that event too. It blocks on a durable path the command
# made dirty or changed again. It catches every writer, including an unknown one,
# because it never has to recognize the tool.
#
# It compares instead of reading the tree alone, because the tree also holds
# what others left there. In the field one stale file blocked 30 later
# commands, reads included, and another session's half-finished merge was
# blamed on unrelated commands. A skip keyed on the merge marker failed: a
# `touch` of the marker let a staged write through. The comparison trusts no
# marker. Paths that were dirty before and that the command left alone pass.
#
# Each record is the porcelain status, the index entry, a hash of the file in
# the working tree, and the path. So a second edit to a dirty file, or a
# `git add` of one, counts as this command's change.
#
# The snapshot lives in <git-dir>/hone-dirty/<session>.<tool-use id>, so
# parallel sessions and parallel calls of one session never share one. With no
# snapshot (no ids in the input, or the step before did not run) the hook
# fails closed: it blocks on every dirty durable path, as before the
# comparison existed.
#
# A write that lands between two commands, such as one from a background job,
# is in the next command's snapshot, so the comparison alone never reports
# it. The session's baseline, <git-dir>/hone-dirty/<session>, holds the
# records its last check saw. Each check rewrites it. A record in a snapshot
# but not in the baseline changed outside any command, and that call's check
# reports it, once, with no restore, since a person's edit looks the same.
# The session's first command only writes the baseline, so work older than
# the session never blocks. Parallel calls of one session share the
# baseline, so the first check to see a write reports it and the others skip
# it. A write that lands during a command is still blamed on it. When
# another call of the session ran at the same time, the block says the
# change may be that call's. Baselines go after 30 days.
#
# It reports AFTER the write, so it cannot prevent the edit. It stops the run
# before the commit, which is where the damage happens. bash-guard.sh rule 4 is
# the preventive half: it escalates the common writers by name, BEFORE they run.
#
# The same .hone-off marker that disables the rest of hone disables this hook.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/messages.sh"

# The command itself is never read: an obfuscated command and a plain one
# leave the same dirty paths. Only the harness's own fields are.
INPUT=$(cat)
if command -v jq >/dev/null 2>&1; then
    IFS=$'\037' read -r EVENT SESSION TOOL_USE < <(printf '%s' "$INPUT" \
        | jq -r '[.hook_event_name, .session_id, .tool_use_id] | map(. // "" | tostring) | join("\u001f")' 2>/dev/null)
else
    EVENT=$(hone_extract_top_field "$INPUT" hook_event_name)
    SESSION=$(hone_extract_top_field "$INPUT" session_id)
    TOOL_USE=$(hone_extract_top_field "$INPUT" tool_use_id)
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0
[ -f ".hone-off" ] && exit 0

# The primary tree only. In a linked worktree the per-worktree git dir differs
# from the common git dir. A dirty durable path there is the work in progress,
# exactly where hone wants it.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
GIT_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null)
COMMON_DIR=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
[ -n "$GIT_DIR" ] && [ "$GIT_DIR" = "$COMMON_DIR" ] || exit 0

# The ids become a file name, so only safe characters survive. Both must be
# present, or two calls could share a name.
SNAP_DIR="$GIT_DIR/hone-dirty"
SNAP=""; BASE=""
SESSION="${SESSION//[^A-Za-z0-9_-]/}"
TOOL_USE="${TOOL_USE//[^A-Za-z0-9_-]/}"
[ -n "$SESSION" ] && [ -n "$TOOL_USE" ] && SNAP="$SNAP_DIR/$SESSION.$TOOL_USE"
# The session's baseline: the records its last check saw, with no dot in the
# name, so the one-day prune of the snapshots passes it by.
[ -n "$SESSION" ] && BASE="$SNAP_DIR/$SESSION"

# The dirty durable paths, into PATHS, XYS, and RECORDS (one per path, in the
# same order). --no-optional-locks keeps this read out of the index lock. This
# hook runs around every Bash call, and the primary tree is shared, so a plain
# status could race another session's commit or land. -z keeps a path with a
# space or a quote intact. -uall lists each file of an untracked directory, so
# a later write to one of them changes its own record. A porcelain record is
# "XY <path>". A rename or a copy adds a second, bare record holding the
# original path, so track that record and read it whole. That original path is
# tracked in HEAD, which is why this loop gives it the R status.
PATHS=(); XYS=(); RECORDS=()
collect() {
    local entry xy path expect_orig=0
    while IFS= read -r -d '' entry; do
        if [ "$expect_orig" -eq 1 ]; then
            path="$entry"; xy="R "; expect_orig=0
        else
            xy="${entry:0:2}"
            case "$xy" in *R*|*C*) expect_orig=1 ;; esac
            path="${entry:3}"
        fi
        [ -n "$path" ] || continue
        hone_is_durable "$path" || continue
        PATHS+=("$path"); XYS+=("$xy")
    done < <(git --no-optional-locks status --porcelain -z -uall 2>/dev/null)
    [ "${#PATHS[@]}" -gt 0 ] || return 0

    # The hashes run only for dirty durable paths, which a healthy primary tree
    # has none of, so a clean tree costs one status call. hash-object takes the
    # paths as arguments and prints one hash per path, in order. ls-files takes
    # them literally, so a path with a glob character matches only itself.
    local -A wt=() idx=()
    local -a files=() hashes=()
    local i line
    for path in "${PATHS[@]}"; do
        [ -f "$path" ] && files+=("$path")
    done
    if [ "${#files[@]}" -gt 0 ]; then
        mapfile -t hashes < <(git hash-object -- "${files[@]}" 2>/dev/null)
        for i in "${!files[@]}"; do wt["${files[$i]}"]="${hashes[$i]:-?}"; done
    fi
    while IFS= read -r -d '' line; do
        path="${line#*$'\t'}"
        idx["$path"]+="${line%%$'\t'*};"
    done < <(git --no-optional-locks --literal-pathspecs ls-files --stage -z -- "${PATHS[@]}" 2>/dev/null)
    for i in "${!PATHS[@]}"; do
        path="${PATHS[$i]}"
        RECORDS+=("${XYS[$i]}|${idx[$path]:--}|${wt[$path]:--}|$path")
    done
}
collect

# Other calls of this session in flight now: their snapshots, less this one's.
# A snapshot older than the longest foreground call is a denied command's, so
# it does not count.
others_in_flight() {
    [ -n "$SESSION" ] && [ -d "$SNAP_DIR" ] || return 1
    find "$SNAP_DIR" -maxdepth 1 -type f -name "$SESSION.*" ! -name '*.tmp*' \
        ! -path "$SNAP" -mmin -10 2>/dev/null | grep -q .
}

# Write the records $@ to file $BASE, atomically, since parallel calls share it.
write_base() {
    [ -n "$BASE" ] || return 0
    if [ "$#" -gt 0 ]; then
        printf '%s\0' "$@" > "$BASE.tmp.$$" 2>/dev/null
    else
        : > "$BASE.tmp.$$" 2>/dev/null
    fi && mv -f "$BASE.tmp.$$" "$BASE"
}

if [ "$EVENT" = "PreToolUse" ]; then
    # Record, never block. A write that fails leaves no snapshot, and the step
    # after then fails closed. The snapshot holds the records, then an empty
    # separator, then the records that changed since the session's last
    # check, then an empty separator and a mark when another call was in
    # flight.
    [ -n "$SNAP" ] || exit 0
    mkdir -p "$SNAP_DIR" 2>/dev/null || exit 0
    OUTSIDE=()
    if [ -f "$BASE" ]; then
        declare -A SEEN=()
        while IFS= read -r -d '' rec; do SEEN["$rec"]=1; done < "$BASE"
        for rec in "${RECORDS[@]}"; do
            [ -n "${SEEN[$rec]:-}" ] || OUTSIDE+=("$rec")
        done
    fi
    OVERLAP=""
    others_in_flight && OVERLAP=1
    write_base "${RECORDS[@]}"
    { [ "${#RECORDS[@]}" -eq 0 ] || printf '%s\0' "${RECORDS[@]}"
      printf '\0'
      [ "${#OUTSIDE[@]}" -eq 0 ] || printf '%s\0' "${OUTSIDE[@]}"
      [ -z "$OVERLAP" ] || printf '\0overlap\0'
    } > "$SNAP.tmp" 2>/dev/null && mv -f "$SNAP.tmp" "$SNAP"
    exit 0
fi

# After the command. Read this call's snapshot and delete it. A denied command
# never reaches this step, so its snapshot stays, and a day later it goes.
HAVE_SNAP=0; OVERLAP=""
declare -A BEFORE=() BEFORE_PATH=() OUT=() SEEN=()
if [ -n "$SNAP" ] && [ -f "$SNAP" ]; then
    HAVE_SNAP=1
    part=0
    while IFS= read -r -d '' rec; do
        if [ -z "$rec" ]; then part=$((part+1)); continue; fi
        case "$part" in
            0) BEFORE["$rec"]=1; BEFORE_PATH["${rec#*|*|*|}"]=1 ;;
            1) OUT["$rec"]=1 ;;
            *) OVERLAP=1 ;;
        esac
    done < "$SNAP"
    # Another call of this session began or ended during this one when it
    # rewrote the baseline after this snapshot, or is still running.
    { [ -f "$BASE" ] && [ "$BASE" -nt "$SNAP" ]; } && OVERLAP=1
    others_in_flight && OVERLAP=1
    rm -f "$SNAP"
    # A record already in the baseline was reported by a parallel call's
    # check, or is one this call saw before it ran.
    if [ -f "$BASE" ]; then
        while IFS= read -r -d '' rec; do SEEN["$rec"]=1; done < "$BASE"
    fi
fi
[ -d "$SNAP_DIR" ] && find "$SNAP_DIR" -maxdepth 1 -type f \( -name '*.*' -mmin +1440 -o -mmin +43200 \) -delete 2>/dev/null

CHANGED=""; RESTORE=""; PRIOR=""; OUTSIDE=""
for i in "${!RECORDS[@]}"; do
    rec="${RECORDS[$i]}"
    path="${PATHS[$i]}"
    if [ -n "${BEFORE[$rec]:-}" ]; then
        # Present before this command. It changed between two checks if the
        # session had not seen it then.
        [ -n "${OUT[$rec]:-}" ] && OUTSIDE+="${OUTSIDE:+$'\n'}$path"
        continue
    fi
    [ -n "${SEEN[$rec]:-}" ] && continue
    CHANGED+="${CHANGED:+$'\n'}$path"
    if [ -n "${BEFORE_PATH[$path]:-}" ]; then
        PRIOR+="${PRIOR:+$'\n'}$path"
    elif [ "${XYS[$i]}" != "??" ]; then
        # One restore command covering every tracked path that was clean
        # before, on one line, so the reader pastes it whole. `git checkout
        # HEAD --` names the commit on purpose. A plain `git checkout --`
        # restores from the INDEX, so a staged write survives it. An untracked
        # path is in no commit, so no checkout restores it.
        RESTORE="${RESTORE:-git checkout HEAD --} '$path'"
    fi
done

# The session has now seen the tree as it is, reported or not.
write_base "${RECORDS[@]}"

[ -n "$CHANGED" ] || [ -n "$OUTSIDE" ] || exit 0

if [ "$HAVE_SNAP" -eq 0 ]; then
    hone_stop_block "$(msg_dirtyguard_no_snapshot "$CHANGED")"
    exit 0
fi
REASON=""
[ -z "$CHANGED" ] || REASON=$(msg_dirtyguard_primary_tree "$CHANGED" "$RESTORE" "$PRIOR" "$OVERLAP")
[ -z "$OUTSIDE" ] || REASON+="${REASON:+$'\n\n'}$(msg_dirtyguard_outside "$OUTSIDE" "$OVERLAP")"
hone_stop_block "$REASON"
exit 0
