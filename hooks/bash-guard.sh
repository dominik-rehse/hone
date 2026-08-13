#!/bin/bash
# PreToolUse guard for Bash commands (Claude Code).
#
# Tamper resistance for hone's enforcement. The Write/Edit deny rules in
# settings.json stop the file tools; this closes the obvious SHELL routes around
# them and around the gate. The threat model is a friction-avoiding agent that
# takes an open path, not an adversary, so this is a DETERRENT, not a sandbox:
# multi-step obfuscation (write-a-script-then-run-it, `python -c`, base64) can
# still evade string matching. It deters and makes tampering attributable.
#
#   deny: unambiguous attempts to disable the gate or its markers
#   ask:  a mutating op aimed at a protected artifact (escalate to the human)
#
# Disabled by the same .hone-off marker that turns off the rest of hone.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/messages.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0
[ -f ".hone-off" ] && exit 0

# $1 = deny|ask, $2 = a template from messages.sh (already prefixed).
decision() { hone_pretool_decision "$1" "$2"; exit 0; }

# Sabotage tokens, defined ONCE and shared by both scan paths so they can't drift.
# HARD_TOKENS always mean "disable the gate wholesale": sabotage on any path.
# MARKER_TOKENS are context-dependent: CREATING .hone-off disables hone, and
# WRITING a grant or proof sign-off usurps the two land gates reserved to the
# human (both denied via the constructs below), but reading or removing one is
# legitimate, so a bare mention only escalates on the fail-closed backstop,
# never auto-denies.
HARD_TOKENS='--no-verify|core\.hooksPath'
MARKER_TOKENS='\.hone-off|\.hone-(grant|proof)/|worktree\.sh[^|;&]*[[:space:]](grant|attest)'

INPUT=$(cat)
CMD=$(hone_extract_field "$INPUT" command)

if [ -z "$CMD" ]; then
    # Parsing failed. Fail closed: if the raw payload carries any gate-sabotage
    # token, escalate; otherwise nothing actionable, so allow.
    if echo "$INPUT" | grep -Eq "$HARD_TOKENS|$MARKER_TOKENS"; then
        decision ask "$(msg_bashguard_unparsed)"
    fi
    exit 0
fi

# 1. Unambiguous gate / marker sabotage → deny: a hard token, or a shell
# construct that CREATES .hone-off.
#
# Only CREATION counts. `echo` and `printf` used to match on a bare mention of
# the marker, so a read-only existence check (`ls .../.hone-off || echo "no
# .hone-off marker present"`) was denied as sabotage. The redirect rule below
# already catches every command that writes the marker, whichever program
# produces the text, so the two creation verbs that write no redirect (touch,
# install) are the whole list.
if echo "$CMD" | grep -Eq \
        -e "$HARD_TOKENS" \
        -e '(^|[^A-Za-z_])(HUSKY|LEFTHOOK|GIT_CONFIG[A-Z_]*)=' \
        -e '(touch|install)[^|;&]*\.hone-off' \
        -e '>[[:space:]]*[^|;&[:space:]]*\.hone-off'; then
    decision deny "$(msg_bashguard_sabotage)"
fi

# 1b. Writing an authority grant or a proof sign-off → deny. The land gates'
# exits 7 and 8 are reserved to the human: the agent never authorizes an
# irreversible change or attests a real-environment check, by any route: a
# file write into .hone-grant/ or .hone-proof/, or the grant/attest helper.
# The mutating-op list is a superset of rule 2's below (creation verbs plus
# every mutator), so a token rule 2 treats as a write cannot slip past here.
if echo "$CMD" | grep -Eq \
        -e '(touch|install|printf|echo|tee|cp|mv|mkdir|ln|sed -i|rm |truncate|dd|chmod|chattr)[^|;&]*\.hone-(grant|proof)/' \
        -e '>>?[[:space:]]*"?'"'"'?[^[:space:]|;&]*\.hone-(grant|proof)/' \
        -e 'worktree\.sh"?'"'"'?[[:space:]]+(grant|attest)([[:space:]]|$)'; then
    decision deny "$(msg_bashguard_signoff)"
fi

# 2. A mutating operation aimed at a protected artifact → ask. The committed
# policy files are protected too: editing .hone-durable-paths,
# .hone-irreversible-paths, or the .hone-proof-always marker shrinks or widens
# the enforcement perimeter, which is the human's call. Deleting the marker is
# the cheapest way past the land proof gate, so it escalates like the rest.
PROT='scripts/run-tests\.sh|scripts/typecheck\.sh|scripts/lint\.sh|scripts/proof\.sh|hooks/(guard|gate|nag|bash-guard|session-start|common|messages)\.sh|\.claude/settings(\.local)?\.json|\.hone-durable-paths|\.hone-(irreversible|consequential)-paths|\.hone-proof-always'
if echo "$CMD" | grep -Eq "(>>?|tee|sed -i|cp |mv |install |ln -s|chmod|chattr|rm |truncate|dd of=)[^|;&]*(${PROT})"; then
    decision ask "$(msg_bashguard_protected)"
fi

# Rules 3 and 4 both apply to the primary tree alone. They need the tree the
# command WRITES IN, which is not always the tree the hook stands in: a
# PreToolUse hook runs in the session's cwd, so `cd .worktrees/x && bun install`
# is worktree work judged from the primary tree. Both rules then misfire, and
# rule 4 tells the agent to move work into a worktree that it already moved.
# So read a leading `cd <target>` and resolve against that target instead.
#
# Fail closed on anything unclear, which keeps the escalation rather than
# dropping it: more than one cd (a command that returns to the primary tree
# must never read as worktree work), a cd that is not first, or a target that
# is not a directory. Each case falls back to the hook's own cwd.
TREE_DIR="$PWD"
if [ "$(printf '%s\n' "$CMD" | grep -Eo '(^|[;&|][[:space:]]*)cd[[:space:]]' | wc -l)" -eq 1 ]; then
    CD_TARGET=$(printf '%s' "$CMD" | sed -n \
        "s/^[[:space:]]*cd[[:space:]]\{1,\}\(\"[^\"]*\"\|'[^']*'\|[^[:space:];&|]\{1,\}\).*/\1/p")
    CD_TARGET=${CD_TARGET%\"}; CD_TARGET=${CD_TARGET#\"}
    CD_TARGET=${CD_TARGET%\'}; CD_TARGET=${CD_TARGET#\'}
    [ -n "$CD_TARGET" ] && [ -d "$CD_TARGET" ] && TREE_DIR="$CD_TARGET"
fi

# git-dir == common-dir ⇔ TREE_DIR is the primary tree, not a linked worktree
# (whose git-dir sits under .git/worktrees/), so neither rule fires for work
# aimed at a worktree, which is where both operations are safe and belong.
IN_PRIMARY_TREE=0
[ "$(git -C "$TREE_DIR" rev-parse --git-dir 2>/dev/null)" \
  = "$(git -C "$TREE_DIR" rev-parse --git-common-dir 2>/dev/null)" ] \
    && IN_PRIMARY_TREE=1

# 3. A HEAD-moving git op in the PRIMARY tree → ask. The primary tree is a merge
# target kept on the trunk; landing goes through `worktree.sh land`, which
# serializes the merge under a lock. Moving the shared HEAD by hand (a branch
# switch, a stash, a hard reset) races every other session that shares this
# tree: the exact collision this guards. Investigation belongs in a throwaway
# `git worktree add --detach`. `git checkout` has its own rule below, because
# one of its forms restores files and moves no HEAD.
if [ "$IN_PRIMARY_TREE" -eq 1 ] \
   && echo "$CMD" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+((switch|stash)([[:space:]]|$)|reset[^|;&]*--(hard|merge|keep))'; then
    decision ask "$(msg_bashguard_head_move)"
fi

# 3b. `git checkout` moves HEAD in one form and restores files in another, so it
# needs the extra look rule 3 does not. `git checkout -- <paths>` and `git
# checkout <ref> -- <paths>` write files and leave HEAD where it is, which is
# the sanctioned way to undo a bad edit in the primary tree. Flagging them sent
# the operator to a scratch worktree to restore two files.
#
# The `--` pathspec separator is the signal, read per command segment so a
# restore later in the line cannot excuse a real HEAD move earlier in it.
# Residual false positive: `git checkout <file>` without the separator is
# indistinguishable from `git checkout <branch>` here, so it still asks.
if [ "$IN_PRIMARY_TREE" -eq 1 ]; then
    while IFS= read -r seg; do
        printf '%s\n' "$seg" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+checkout([[:space:]]|$)' || continue
        printf '%s\n' "$seg" | grep -Eq '[[:space:]]--([[:space:]]|$)' && continue
        decision ask "$(msg_bashguard_head_move)"
    done < <(printf '%s\n' "$CMD" | tr '|;&' '\n\n\n')
fi

# 4. A tool that writes its OWN files, run in the PRIMARY tree → ask. This is
# the preventive half of the primary-tree rule for the shell route, and
# dirty-guard.sh (PostToolUse) is the half that catches what this list misses.
# Rule 2 above cannot see these: a package manager rewrites package.json from
# inside its own process, so the command text carries neither a write construct
# nor the path.
#
# This is an allow-list of names, so it DRIFTS by construction: a new package
# manager, a new migrate subcommand, or a wrapper script that calls one is a
# hole until someone adds it here. That is why it only escalates, and why
# dirty-guard checks the effect instead. Keep the boundary loose (a writer
# anywhere in the command, so `bunx biome migrate` and `sudo npm install` both
# match) and accept that prose quoting one of these names also escalates: an
# ask costs one keystroke, and a missed dependency sweep costs a bad commit.
#
# A BARE SYNC INSTALL is the exception: `bun install`, `npm ci`, `poetry
# install`, with flags only, installs what the lockfile already says and writes
# no durable file. It is also the sanctioned next step after a land that changed
# the lockfile, and this rule used to escalate it. Whatever such a command does
# dirty, dirty-guard sees: the effect net behind this rule catches any write to
# a durable path, so a preventive ask here buys nothing.
#
# The verb's argument tells the two apart: end of command or flag tokens only
# means sync, and a non-flag argument names a package, which mutates the
# manifest. So `npm install lodash`, `bun add x`, and `poetry add y` still
# escalate, as does every add/remove/update/upgrade/link verb below.
NAMED_ARG='([[:space:]]+-[^[:space:];&|]*)*[[:space:]]+[^-[:space:];&|]'
SELF_WRITERS='(npm|pnpm|yarn|bun|deno)[[:space:]]+(add|remove|rm|uninstall|update|upgrade|up|link|pkg)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(npm|pnpm|yarn|bun|deno)[[:space:]]+(install|i|ci)'"$NAMED_ARG"
SELF_WRITERS="$SELF_WRITERS"'|(pip|pip3|uv|poetry|cargo|bundle|gem|mix|composer)[[:space:]]+(add|remove|uninstall|lock|update|upgrade|require|fmt)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(pip|pip3|uv|poetry|cargo|bundle|gem|mix|composer)[[:space:]]+(install|sync|deps\.get)'"$NAMED_ARG"
SELF_WRITERS="$SELF_WRITERS"'|go[[:space:]]+(get|mod)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(biome|eslint|prettier|dprint|ruff|black|isort|rustfmt|gofmt|jscodeshift|codemod)[^|;&]*(migrate|--write|--fix|--apply|[[:space:]]-w([[:space:]]|$)|[[:space:]]fmt([[:space:]]|$)|[[:space:]]format([[:space:]]|$))'
if [ "$IN_PRIMARY_TREE" -eq 1 ] && echo "$CMD" | grep -Eq "(^|[^A-Za-z0-9_.-])(${SELF_WRITERS})"; then
    decision ask "$(msg_bashguard_self_writer)"
fi

exit 0
