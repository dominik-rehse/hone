#!/bin/bash
# PostToolUse guard for Bash commands (Claude Code). It closes the one hole
# the other two guards cannot see.
#
# guard.sh reads a file path, so it only fires when a FILE TOOL produces one.
# bash-guard.sh reads the command text, so it only fires when the command SPELLS
# OUT both a write construct and a protected path. A tool that writes its own
# files satisfies neither. `bun add` rewrites package.json from inside its own
# process, so no write construct and no path ever appear in the command. Rule 1
# of guard.sh, the primary-tree rule, therefore missed every such write.
#
# This hook checks the EFFECT instead of the command. In the primary tree it
# asks git what the command actually left dirty, and blocks when any dirty path
# is durable. It catches every writer, including an unknown one,
# because it never has to recognize the tool.
#
# It reports AFTER the write, so it cannot prevent the edit. It stops the run
# before the commit, which is where the damage happens. bash-guard.sh rule 4 is
# the preventive half: it escalates the common writers by name, BEFORE they run.
#
# A healthy primary tree carries nothing uncommitted, so a dirty durable path
# is already the violation signal. The same .hone-off marker that disables the
# rest of hone disables this hook.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/messages.sh"

# Drain stdin. This hook reads the tree, never the command, so it parses
# nothing: an obfuscated command and a plain one leave the same dirty paths.
cat >/dev/null

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

# Collect the dirty durable paths. --no-optional-locks keeps this read out of
# the index lock. This hook runs after every Bash call, and the primary tree is
# shared, so a plain status could race another session's commit or land. -z
# keeps a path with a space or a quote intact, which the quoted default format
# would break. A porcelain record is "XY <path>". A rename or a copy adds a
# second, bare record holding the original path, so track that record and read
# it whole. That original path is tracked in HEAD, which is why this loop gives
# it the R status.
#
# A merge, cherry-pick, revert, or rebase in progress leaves its own results
# staged, and its conflicts unmerged. The command that started it went past
# the bash-guard's ask, often in another session. So while one is in progress,
# a staged or unmerged path is the operation's, not this command's, and the
# hook leaves it out. It used to blame every later command of every session
# for another session's half-finished merge. A path changed only in the
# working tree, or an untracked one, still counts.
IN_OP=0
for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [ -e "$GIT_DIR/$marker" ] && { IN_OP=1; break; }
done
DIRTY=""
TRACKED=""
expect_orig=0
while IFS= read -r -d '' entry; do
    if [ "$expect_orig" -eq 1 ]; then
        path="$entry"; xy="R "; expect_orig=0
    else
        xy="${entry:0:2}"
        case "$xy" in *R*|*C*) expect_orig=1 ;; esac
        path="${entry:3}"
    fi
    [ -n "$path" ] || continue
    if [ "$IN_OP" -eq 1 ]; then
        case "$xy" in "??"|" "?) ;; *) continue ;; esac
    fi
    hone_is_durable "$path" || continue
    DIRTY+="${DIRTY:+$'\n'}$path"
    [ "$xy" = "??" ] || TRACKED+="${TRACKED:+$'\n'}$path"
done < <(git --no-optional-locks status --porcelain -z 2>/dev/null)

[ -n "$DIRTY" ] || exit 0

# One restore command covering every TRACKED path, on one line, so the reader
# pastes it whole. `git checkout HEAD --` names the commit on purpose. A plain
# `git checkout --` restores from the INDEX, so a staged write survives it and
# the command reads as a no-op. An untracked path is in no commit, so no
# checkout restores it and the message asks the reader to remove it instead.
RESTORE=""
if [ -n "$TRACKED" ]; then
    RESTORE="git checkout HEAD --"
    while IFS= read -r path; do
        RESTORE+=" '$path'"
    done <<<"$TRACKED"
fi

hone_stop_block "$(msg_dirtyguard_primary_tree "$DIRTY" "$RESTORE")"
exit 0
