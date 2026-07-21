#!/bin/bash
# PreToolUse guard for Write/Edit/MultiEdit (Claude Code). Enforces two laws of
# the hone model, in this order:
#
#   1. The primary tree is a merge target, never a workspace. A Write/Edit to a
#      durable committed artifact (src/, tests/, docs/, db/, plus any paths the
#      project lists in .hone-durable-paths) in the PRIMARY git tree is denied —
#      that work belongs in a worktree, landed by a merge. The hand-written Plan
#      (.plans/) — tracked, but authored and committed here in the primary tree —
#      and local config are exempt.
#
#   2. No production code without a failing test. Creating a NEW non-test file
#      under src/ is denied unless a test file for it already exists. Test files
#      (the RED artifact) are always writable; editing an existing src/ file is
#      allowed (its test was required when it was created).
#
# Rule 1 needs a git repo to tell primary from worktree; without one it is a
# no-op (no worktrees exist, so the model does not apply) and only rule 2 runs.
#
# Input:  JSON on stdin from Claude Code's PreToolUse hook system.
# Output: a deny is a structured PreToolUse decision on stdout
#         (permissionDecision=deny); the process still exits 0. An allow is a
#         silent exit 0.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

# Resolve the project root from the git worktree we are actually in (the hook's
# cwd), so the guard is correct inside a linked worktree — including a
# worktree-isolated subagent, whose cwd is the worktree while CLAUDE_PROJECT_DIR
# stays pinned to the parent. Fall back to CLAUDE_PROJECT_DIR, then cwd.
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0
PROJECT_DIR=$(pwd -P)

# Report a denial as a structured PreToolUse decision. exit 0 keeps the JSON the
# sole channel (a non-zero exit would compete with it).
deny() { hone_pretool_decision deny "hone guard: $*"; exit 0; }

[ -f ".hone-off" ] && exit 0

# Basename globs that identify a test file. A project may override the defaults
# by listing its own (one per line, # comments allowed) in .hone-test-globs.
# The file REPLACES the defaults, so a language whose tests don't match the
# defaults declares its convention there. Empty/all-comment file → defaults.
configured_test_globs() {
    if [ -f ".hone-test-globs" ] && grep -qvE '^[[:space:]]*(#|$)' ".hone-test-globs"; then
        tr -d '\r' < ".hone-test-globs" \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
            | grep -vE '^(#|$)'
    else
        printf '%s\n' '*.test.*' '*.spec.*' '*_test.*' '*_spec.*'
    fi
}

INPUT=$(cat)
FILE_PATH=$(hone_extract_field "$INPUT" file_path)

[ -z "$FILE_PATH" ] && deny "Write/Edit hook input did not include tool_input.file_path."

FILE_PATH="${FILE_PATH#./}"
# `-s` normalizes lexically (collapses ./ and ../) WITHOUT resolving symlinks,
# so a write under a symlinked `src` stays under src/ and is still gated — and a
# symlink pointing outside the project is treated lexically as in-project and
# gated, rather than resolved away and silently allowed (fail-closed).
case "$FILE_PATH" in
    /*) TARGET_PATH=$(realpath -m -s -- "$FILE_PATH") ;;
    *)  TARGET_PATH=$(realpath -m -s -- "$PROJECT_DIR/$FILE_PATH") ;;
esac

case "$TARGET_PATH" in
    "$PROJECT_DIR"/*) REL="${TARGET_PATH#"$PROJECT_DIR"/}" ;;
    *) exit 0 ;;  # outside the project — not ours to guard
esac

# A durable committed artifact is anything under src/, tests/, docs/, or db/
# (schema and migrations are as durable as code), plus any project-specific
# paths listed in .hone-durable-paths (one per line, # comments allowed):
# a directory prefix (`deploy/`) or an exact file (`tsconfig.json`). Unlike
# .hone-test-globs, the file EXTENDS the defaults — the built-in perimeter
# can grow, never shrink.
is_durable() {
    case "$1" in
        src/*|tests/*|docs/*|db/*) return 0 ;;
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

# Rule 1: no direct edits to durable artifacts in the primary tree.
# Distinguish the primary tree from a linked worktree: in the primary tree the
# per-worktree git dir equals the common git dir; in a linked worktree it does
# not. Skip when not a git repo (no worktrees possible → the rule cannot apply).
if git rev-parse --git-dir >/dev/null 2>&1; then
    GIT_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null)
    COMMON_DIR=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
    if [ -n "$GIT_DIR" ] && [ "$GIT_DIR" = "$COMMON_DIR" ] && is_durable "$REL"; then
        deny "$REL is a durable artifact and you are in the primary tree, which is a merge target — never a workspace. Do this change in a worktree (/hone:run spawns one) and let land merge it. Set .hone-off to override."
    fi
fi

# Rule 2: no new production code in src/ without a failing test.
[[ "$REL" == src/* ]] || exit 0
[ -e "$TARGET_PATH" ] && exit 0   # editing an existing src/ file — its test was required at creation

TEST_GLOBS=()
while IFS= read -r _g; do
    [ -n "$_g" ] && TEST_GLOBS+=("$_g")
done < <(configured_test_globs)

# Test files are the RED artifact, always allowed.
BN=$(basename "$REL")
for _g in "${TEST_GLOBS[@]}"; do
    # shellcheck disable=SC2254
    case "$BN" in $_g) exit 0 ;; esac
done

BASE_NO_EXT=$(echo "$REL" | sed 's/\.[^.]*$//')   # e.g. src/auth/login
STEM=$(basename "$BASE_NO_EXT")                    # e.g. login
DIR=$(dirname "$BASE_NO_EXT")                      # e.g. src/auth
FEATURE="${BASE_NO_EXT#src/}"                      # e.g. auth/login
FEATURE_DASH=$(echo "$FEATURE" | tr '/_' '--')
FEATURE_UNDER=$(echo "$FEATURE" | tr '/-' '__')
STEM_DASH=$(echo "$STEM" | tr '_' '-')
STEM_UNDER=$(echo "$STEM" | tr '-' '_')

has_glob_match() {
    local pattern
    local -a matches
    local IFS=
    shopt -s nullglob
    for pattern in "$@"; do
        # shellcheck disable=SC2206
        matches=( $pattern )
        if [ ${#matches[@]} -gt 0 ]; then shopt -u nullglob; return 0; fi
    done
    shopt -u nullglob
    return 1
}

# Build "does a test exist for this file?" candidates from the configured globs:
# co-located next to the src file, and under tests/ in several name forms.
TEST_PATTERNS=()
for _g in "${TEST_GLOBS[@]}"; do
    TEST_PATTERNS+=( "$DIR/${_g/\*/$STEM}" )
    for _f in "$FEATURE" "$FEATURE_DASH" "$FEATURE_UNDER" "$STEM" "$STEM_DASH" "$STEM_UNDER"; do
        TEST_PATTERNS+=( "tests/${_g/\*/$_f}" )
    done
done
# pytest's prefix convention (test_foo.py) can't be a suffix glob; add it.
for _u in "$FEATURE_UNDER" "$STEM_UNDER"; do
    TEST_PATTERNS+=( "tests/test_${_u}".* )
    TEST_PATTERNS+=( "$DIR/test_${_u}".* )
done

if ! has_glob_match "${TEST_PATTERNS[@]}"; then
    deny "$REL has no test — hone is test-first. Write its failing test first (${BASE_NO_EXT}.test.<ext> or tests/${FEATURE}.test.<ext>), watch it fail, then write the code."
fi

exit 0
