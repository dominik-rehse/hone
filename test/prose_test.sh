#!/bin/bash
# Check the shipped prose against the files and commands it names. Three checks,
# all exact, all derived from the repo itself (no hand-kept list):
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
#   3. Surface coverage, the reverse direction. Everything the code exposes
#      must appear in docs/reference.md, the control surface: every
#      worktree.sh subcommand (in the script's own header too), every
#      .hone-* marker or record the hooks and the script read, every
#      HONE_* variable read with a default, and every hook file. A feature
#      that ships without its reference entry fails here. The semantic half
#      (a sentence elsewhere that now states the old behavior) stays a
#      reading job, and .claude/rules/releasing.md names the files to read.
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

echo "== prose: the reference covers the control surface =="
REF=docs/reference.md
HEADER=$(sed -n '1,/^HONE_WSH=/p' scripts/worktree.sh)
gaps=0
while IFS= read -r sub; do
    [ -n "$sub" ] || continue
    grep -qE "worktree\.sh $sub([^a-z-]|$)" "$REF" || { bad "$REF never names 'worktree.sh $sub'"; gaps=$((gaps+1)); }
    printf '%s\n' "$HEADER" | grep -qE "^#   worktree\.sh $sub([^a-z-]|$)" \
        || { bad "the scripts/worktree.sh header has no entry for '$sub'"; gaps=$((gaps+1)); }
done <<<"$subs"
# Markers and records: whatever the hooks and the worktree script read. The
# setup script is left out, because it names markers hone RETIRED (it strips
# their gitignore lines), and those belong in upgrading.md, not here.
while IFS= read -r marker; do
    [ -n "$marker" ] || continue
    grep -qF -- "$marker" "$REF" || { bad "$REF never names $marker"; gaps=$((gaps+1)); }
done < <(grep -ohE '\.hone-[a-z-]+' hooks/*.sh scripts/worktree.sh 2>/dev/null | sort -u)
while IFS= read -r var; do
    [ -n "$var" ] || continue
    grep -qF -- "$var" "$REF" || { bad "$REF never names $var"; gaps=$((gaps+1)); }
done < <(grep -ohE '\$\{HONE_[A-Z_]+:-' hooks/*.sh scripts/*.sh 2>/dev/null | sed 's/[${:-]//g' | sort -u)
for hook in hooks/*.sh; do
    name=$(basename "$hook" .sh)
    case "$name" in common|messages) continue ;; esac
    grep -qF -- "$name" "$REF" || { bad "$REF never names the $name hook"; gaps=$((gaps+1)); }
done
[ "$gaps" -eq 0 ] && ok "every subcommand, marker, tunable, and hook has a reference entry"

echo
echo "prose_test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
