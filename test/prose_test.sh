#!/bin/bash
# Check the shipped prose against the files and commands it names. Two checks,
# both exact, both derived from the repo itself (no hand-kept list):
#
#   1. Path integrity. Prose names a file the plugin ships: a
#      ${CLAUDE_PLUGIN_ROOT}/<path> token, or a skill-relative
#      references/<file>.md token. Each named path must exist in this repo.
#      The eval case missing-reference-holdout pins what the loop DOES when
#      a reference is gone. This check keeps the plugin from shipping one.
#   2. Subcommand integrity. Prose that names a worktree.sh subcommand must
#      name one the script dispatches. The valid set comes from the case
#      statement in scripts/worktree.sh itself, so a rename that misses a
#      prose mention fails here. Convention: backtick a bare `worktree.sh`
#      mention when the next word is prose, so it does not read as a
#      subcommand.
#
# Run: bash test/prose_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PLUGIN_ROOT" || exit 1

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

# The shipped prose: everything a consumer or the model reads.
PROSE=$(find skills agents rules templates docs README.md -type f -name '*.md' 2>/dev/null)

echo "== prose: named plugin files exist =="
missing=0
while IFS= read -r file; do
    while IFS= read -r tok; do
        path=${tok#\$\{CLAUDE_PLUGIN_ROOT\}/}
        path=${path%/}
        if [ ! -e "$path" ]; then
            bad "$file names \${CLAUDE_PLUGIN_ROOT}/$path, which does not exist"
            missing=$((missing+1))
        fi
    done < <(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9/._-]+' "$file" 2>/dev/null | sort -u)
done <<<"$PROSE"
[ "$missing" -eq 0 ] && ok "every \${CLAUDE_PLUGIN_ROOT} path resolves"

# A bare references/<file>.md token resolves against its own skill's root.
# The leading-character guard skips tokens inside a longer path, which the
# ${CLAUDE_PLUGIN_ROOT} check above already covers.
missing=0
while IFS= read -r file; do
    case "$file" in skills/*) ;; *) continue ;; esac
    rest=${file#skills/}
    skill_dir="skills/${rest%%/*}"
    while IFS= read -r tok; do
        if [ ! -e "$skill_dir/$tok" ]; then
            bad "$file names $tok, which $skill_dir/ does not hold"
            missing=$((missing+1))
        fi
    done < <(sed 's/^/ /' "$file" | grep -oE '[^/A-Za-z0-9_]references/[A-Za-z0-9._-]+\.md' | sed 's/^.//' | sort -u)
done <<<"$PROSE"
[ "$missing" -eq 0 ] && ok "every skill-relative references/ path resolves"

echo "== prose: named worktree.sh subcommands exist =="
# shellcheck disable=SC2016  # the sed pattern matches a literal $sub in the script
subs=$(sed -n '/case "\$sub" in/,/esac/p' scripts/worktree.sh | grep -oE '^[[:space:]]*[a-z][a-z-]*\)' | tr -d ' )' | sort -u)
if [ -z "$subs" ]; then
    bad "could not parse the subcommand set out of scripts/worktree.sh"
else
    unknown=0
    while IFS= read -r mention; do
        word=${mention##* }
        if ! printf '%s\n' "$subs" | grep -qxF "$word"; then
            bad "prose names 'worktree.sh $word', which the script does not dispatch"
            unknown=$((unknown+1))
        fi
    # shellcheck disable=SC2086  # $PROSE splits into one path per line, wanted
    done < <(grep -ohE 'worktree\.sh +[a-z][a-z-]*' $PROSE 2>/dev/null | sort -u)
    [ "$unknown" -eq 0 ] && ok "every mentioned subcommand is dispatched ($(printf '%s\n' "$subs" | wc -l) valid)"
fi

echo
echo "prose_test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
