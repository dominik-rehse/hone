#!/bin/bash
# PreToolUse guard for Bash commands (Claude Code).
#
# Tamper resistance for hone's enforcement. The Write/Edit deny rules in
# settings.json stop the file tools; this closes the obvious SHELL routes around
# them and around the gate. The threat model is a friction-avoiding agent that
# takes an open path, not an adversary — so this is a DETERRENT, not a sandbox:
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

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0
[ -f ".hone-off" ] && exit 0

decision() { hone_pretool_decision "$1" "hone bash-guard: $2"; exit 0; }

# Sabotage tokens, defined ONCE and shared by both scan paths so they can't drift.
# HARD_TOKENS always mean "disable the gate wholesale" — sabotage on any path.
# MARKER_TOKENS are context-dependent: CREATING .hone-off disables hone (denied
# via the constructs below), but reading or REMOVING a marker is legitimate, so
# a bare mention only escalates on the fail-closed backstop, never auto-denies.
HARD_TOKENS='--no-verify|core\.hooksPath'
MARKER_TOKENS='\.hone-off|\.hone-(gate-enforce|nag-enforce)'

INPUT=$(cat)
CMD=$(hone_extract_field "$INPUT" command)

if [ -z "$CMD" ]; then
    # Parsing failed. Fail closed: if the raw payload carries any gate-sabotage
    # token, escalate; otherwise nothing actionable, so allow.
    if echo "$INPUT" | grep -Eq "$HARD_TOKENS|$MARKER_TOKENS"; then
        decision ask "could not parse the command, but the payload contains a token associated with disabling the hone gate (e.g. --no-verify, core.hooksPath, .hone-off). Review it manually before allowing."
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
    decision deny "command would disable the hone gate (e.g. --no-verify, core.hooksPath, creating .hone-off). If this is intentional, make the change yourself outside the agent."
fi

# 2. A mutating operation aimed at a protected artifact → ask.
PROT='scripts/run-tests\.sh|scripts/typecheck\.sh|scripts/lint\.sh|hooks/(guard|gate|nag|bash-guard|session-start|common)\.sh|\.claude/settings(\.local)?\.json'
if echo "$CMD" | grep -Eq "(>>?|tee|sed -i|cp |mv |install |ln -s|chmod|chattr|rm |truncate|dd of=)[^|;&]*(${PROT})"; then
    decision ask "command appears to modify a protected hone artifact (the test adapter, a hook, or settings). Confirm this is an intended, legitimate change before allowing it."
fi

# 3. A HEAD-moving git op in the PRIMARY tree → ask. The primary tree is a merge
# target kept on the trunk; landing goes through `worktree.sh land`, which
# serializes the merge under a lock. Moving the shared HEAD by hand (a checkout
# to investigate, a stash, a hard reset) races every other session that shares
# this tree — the exact collision this guards. Investigation belongs in a
# throwaway `git worktree add --detach`. git-dir == common-dir ⇔ the hook's cwd
# is the primary tree, not a linked worktree (whose git-dir sits under
# .git/worktrees/), so the rule never fires inside a worktree where HEAD-moves
# are safely isolated.
if [ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] \
   && echo "$CMD" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+((checkout|switch|stash)([[:space:]]|$)|reset[^|;&]*--(hard|merge|keep))'; then
    decision ask "command moves HEAD in the primary tree (git checkout/switch/stash/reset). The primary tree stays on the trunk as a merge target — investigate in a 'git worktree add --detach' scratch tree, and land via 'worktree.sh land'. Confirm before allowing."
fi

exit 0
