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
if echo "$CMD" | grep -Eq \
        -e "$HARD_TOKENS" \
        -e '(^|[^A-Za-z_])(HUSKY|LEFTHOOK|GIT_CONFIG[A-Z_]*)=' \
        -e '(touch|install|printf|echo)[^|;&]*\.hone-off' \
        -e '>[[:space:]]*"?'"'"'?\.hone-off'; then
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

# Rules 3 and 4 both apply to the primary tree alone. git-dir == common-dir ⇔
# the hook's cwd is the primary tree, not a linked worktree (whose git-dir sits
# under .git/worktrees/), so neither rule fires inside a worktree, which is
# where both operations are safe and belong.
IN_PRIMARY_TREE=0
[ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] \
    && IN_PRIMARY_TREE=1

# 3. A HEAD-moving git op in the PRIMARY tree → ask. The primary tree is a merge
# target kept on the trunk; landing goes through `worktree.sh land`, which
# serializes the merge under a lock. Moving the shared HEAD by hand (a checkout
# to investigate, a stash, a hard reset) races every other session that shares
# this tree: the exact collision this guards. Investigation belongs in a
# throwaway `git worktree add --detach`.
if [ "$IN_PRIMARY_TREE" -eq 1 ] \
   && echo "$CMD" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+((checkout|switch|stash)([[:space:]]|$)|reset[^|;&]*--(hard|merge|keep))'; then
    decision ask "$(msg_bashguard_head_move)"
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
SELF_WRITERS='(npm|pnpm|yarn|bun|deno)[[:space:]]+(add|install|i|ci|remove|rm|uninstall|update|upgrade|up|link|pkg)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(pip|pip3|uv|poetry|cargo|bundle|gem|mix|composer)[[:space:]]+(add|install|remove|uninstall|sync|lock|update|upgrade|require|fmt|deps\.get)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|go[[:space:]]+(get|mod)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(biome|eslint|prettier|dprint|ruff|black|isort|rustfmt|gofmt|jscodeshift|codemod)[^|;&]*(migrate|--write|--fix|--apply|[[:space:]]-w([[:space:]]|$)|[[:space:]]fmt([[:space:]]|$)|[[:space:]]format([[:space:]]|$))'
if [ "$IN_PRIMARY_TREE" -eq 1 ] && echo "$CMD" | grep -Eq "(^|[^A-Za-z0-9_.-])(${SELF_WRITERS})"; then
    decision ask "$(msg_bashguard_self_writer)"
fi

exit 0
