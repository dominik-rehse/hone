#!/bin/bash
# The hygiene checks (hooks/hygiene.sh) through their two callers:
# `worktree.sh hygiene <change>`, scoped to one change, and `worktree.sh
# attention`, the person's list for the primary tree. Then the SessionStart
# hook that shows attention, setup's removal of the retired nag's file, and
# the hooks.json that no longer wires the nag. Each section builds its own
# repository. Run: bash test/hygiene_test.sh
set -uo pipefail
unset HERDR_ENV

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WSH="$PLUGIN_ROOT/scripts/worktree.sh"
SESSION_START="$PLUGIN_ROOT/hooks/session-start.sh"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A fresh repository at $1 on main, with one area, one small Note, and the
# old debts a change must not hear about: an oversized Note, an undated spike,
# a Decision with a broken link, and an area over a small cap.
mkrepo() {
    local r="$1"
    mkdir -p "$r" && cd "$r" || exit 1
    git init -q && git symbolic-ref HEAD refs/heads/main
    git config user.email t@t.t && git config user.name t
    mkdir -p src/auth src/old docs/notes docs/decisions docs/spikes .plans
    printf '.worktrees/\n' > .gitignore
    printf 'one\ntwo\nthree\n' > README.md
    seq 1 5 > src/auth/token.js
    seq 1 50 > src/old/table.js
    printf '# auth\nThe map.\n' > docs/notes/auth.md
    seq 1 60 > docs/notes/old.md
    printf '# legacy\n' > docs/spikes/legacy.md
    printf '# Old\nSee [gone](../gone.md).\n' > docs/decisions/old.md
    git add -A && git commit -qm seed
    cd - >/dev/null || exit 1
}

# Run hygiene for change $2 from directory $1. Sets $out and $rc.
hy() { out=$(cd "$1" && HONE_AREA_MAX_LINES="${CAP:-3000}" bash "$WSH" hygiene "$2" 2>&1); rc=$?; }
# Run attention from directory $1 (extra arguments pass through). Sets $out and $rc.
attn() { local d="$1"; shift; out=$(cd "$d" && bash "$WSH" attention "$@" 2>&1); rc=$?; }
has() { printf '%s\n' "$out" | grep -qF -- "$1"; }

# Each change, twice: live in its worktree, then committed with the worktree
# gone, so the branch alone is read. $1 = the repo, $2 = the change, $3 = a
# shell snippet that makes the change inside the worktree, $4.. = checks, each
# "want|<text>" or "none|<text>", then "rc=<n>".
both_modes() {
    local r="$1" change="$2" make="$3"; shift 3
    local wt="$r/.worktrees/$change" mode c want text
    (cd "$r" && bash "$WSH" add "$change" >/dev/null 2>&1) || { bad "$change: add failed"; return; }
    (cd "$wt" && eval "$make")
    for mode in worktree branch; do
        if [ "$mode" = branch ]; then
            (cd "$wt" && git add -A && git commit -qm "change $change")
            git -C "$r" worktree remove --force "$wt"
        fi
        hy "$r" "$change"
        for c in "$@"; do
            want=${c%%|*}; text=${c#*|}
            case "$want" in
                want) has "$text" && ok "$change ($mode): prints '$text'" || bad "$change ($mode): should print '$text': $out" ;;
                none) has "$text" && bad "$change ($mode): should not print '$text': $out" || ok "$change ($mode): no '$text'" ;;
                rc=*) [ "$rc" = "${want#rc=}" ] && ok "$change ($mode): exit ${want#rc=}" || bad "$change ($mode): exit $rc, want ${want#rc=}: $out" ;;
            esac
        done
    done
}

echo "== hygiene: a change that cuts something, and old debts out of scope =="
R="$TMP/r1"; mkrepo "$R"
CAP=30 both_modes "$R" clean 'printf "one\ntwo\nfour\n" > README.md' \
    'rc=0|' 'none|deletes nothing' 'none|docs/notes/old.md' 'none|legacy' 'none|docs/decisions/old.md' 'none|src/old/'
hy "$R" clean; [ -z "$out" ] && ok "clean: a clean change prints nothing" || bad "clean: should print nothing: $out"

echo "== hygiene: a change that deletes nothing (check 4) =="
both_modes "$R" additive 'echo new > added.txt' \
    'rc=1|' 'want|Fix now:' 'want|This change deletes nothing (+1/-0 against main).' "want|say why in the commit's Cut: line"
# Uncommitted work counts: a deletion not yet committed is still a cut.
(cd "$R" && bash "$WSH" add pending-cut >/dev/null 2>&1)
(cd "$R/.worktrees/pending-cut" && echo more > more.txt && git add -A && git commit -qm add && printf 'one\n' > README.md)
hy "$R" pending-cut
has 'deletes nothing' && bad "an uncommitted deletion should count: $out" || ok "an uncommitted deletion counts as a cut"
(cd "$R/.worktrees/pending-cut" && git checkout -q README.md && echo untracked > new.txt)
hy "$R" pending-cut
has 'deletes nothing (+2/-0' && ok "an untracked file counts as insertions" || bad "untracked lines should count: $out"
git -C "$R" worktree remove --force "$R/.worktrees/pending-cut"

echo "== hygiene: a Note the change touched (checks 2 and 3) =="
both_modes "$R" note-big 'seq 1 45 > docs/notes/auth.md; sed -i 1d README.md' \
    'rc=1|' 'want|docs/notes/auth.md is 45 lines, over the 40-line cap.' 'none|docs/notes/old.md'
both_modes "$R" note-small 'printf "# auth\nA shorter map.\n" > docs/notes/auth.md' \
    'rc=0|' 'none|docs/notes/auth.md'
both_modes "$R" note-orphan 'printf "# ghost\n" > docs/notes/ghost.md; sed -i 1d README.md' \
    'rc=1|' 'want|docs/notes/ghost.md has no src/ghost/ directory beside it.'
# The change deleted the area and left its Note untouched.
both_modes "$R" area-gone 'git rm -rq src/auth' \
    'rc=1|' 'want|docs/notes/auth.md has no src/auth/ directory beside it.'

echo "== hygiene: a spike entry the change added (check 8) =="
both_modes "$R" spike-undated 'mkdir -p docs/spikes/probe && echo x > docs/spikes/probe/run.sh; sed -i 1d README.md' \
    'rc=1|' 'want|docs/spikes/probe carries no date at the front of its name.' 'none|legacy'
both_modes "$R" spike-dated 'echo x > docs/spikes/2026-10-09-probe.md; sed -i 1d README.md' \
    'rc=0|' 'none|carries no date'
# An old undated entry that the change only edits was not added by it.
both_modes "$R" spike-old 'echo more >> docs/spikes/legacy.md; sed -i 1d README.md' \
    'rc=0|' 'none|carries no date'

echo "== hygiene: Governs: paths and relative links (checks 6 and 9) =="
both_modes "$R" governs 'printf "# Export\nGoverns: src/ghost/gone.ts\n" > docs/decisions/export.md; sed -i 1d README.md' \
    'rc=1|' 'want|docs/decisions/export.md declares Governs: src/ghost/gone.ts, which no longer exists.'
both_modes "$R" governs-live 'printf "# Auth\nGoverns: src/auth, src/auth/token.js.\n" > docs/decisions/auth.md; sed -i 1d README.md' \
    'rc=0|' 'none|declares Governs'
both_modes "$R" link-broken 'printf "# Export\nSee [the old spike](../spikes/2024-01-01-gone.md).\n" > docs/decisions/export.md; sed -i 1d README.md' \
    'rc=1|' 'want|docs/decisions/export.md links to ../spikes/2024-01-01-gone.md, which does not resolve.'
both_modes "$R" link-fine 'printf "# Auth\nSee [the note](../notes/auth.md), [the spec](https://example.org/x), [above](#why).\n" > docs/decisions/auth.md; sed -i 1d README.md' \
    'rc=0|' 'none|links to'
# A link shown as code is an example, and a target with any URI scheme is no
# file. A Decision quoting `[x](javascript:…)` once printed a finding on every stop.
cat > "$TMP/render.md" <<'MD'
# Rendering
Dangerous URLs (`[x](javascript:…)`, `![](data:…)`) and a ``[y](gone-too.md)`` span.
Call [the desk](tel:+4912345) or run [the probe](javascript:void(0)).
```md
[an example](not-a-file.md)
```
~~~
[another](also-not-a-file.md)
~~~
See [the gone one](../spikes/2024-02-02-gone.md).
MD
both_modes "$R" link-code "cp '$TMP/render.md' docs/decisions/render.md; sed -i 1d README.md" \
    'rc=1|' 'none|links to javascript' 'none|links to data' 'none|links to tel' 'none|gone-too.md' \
    'none|not-a-file.md' 'want|docs/decisions/render.md links to ../spikes/2024-02-02-gone.md'
# A Decision the change never opened, about code the change touched.
git -C "$R" checkout -q main
printf '# Tokens\nGoverns: src/auth/\nSee [the gone](../gone-too.md).\n' > "$R/docs/decisions/tokens.md"
(cd "$R" && git add -A && git commit -qm "docs: tokens")
both_modes "$R" governed-doc 'echo 6 >> src/auth/token.js; sed -i 1d README.md' \
    'rc=1|' 'want|docs/decisions/tokens.md links to ../gone-too.md' 'none|docs/decisions/old.md'
(cd "$R" && git rm -q docs/decisions/tokens.md && git commit -qm "docs: drop tokens")

echo "== hygiene: an area the change touched, over the cap (check 11) =="
CAP=30 both_modes "$R" area-big 'seq 1 40 > src/auth/big.js; head -c 4000 /dev/urandom > src/auth/blob.bin; sed -i 1d README.md' \
    'rc=0|' 'want|For the person:' 'want|src/auth/ holds 45 lines, over the 30-line cap, and this change touched it.' \
    'none|Fix now:' 'none|src/old/'
CAP=3000 both_modes "$R" area-small 'seq 1 40 > src/auth/big.js; sed -i 1d README.md' \
    'rc=0|' 'none|holds'
# Generated files do not count: linguist-generated in .gitattributes, or a
# generated header. A generated output.css was 11,699 of 17,764 lines in one area.
GEN='mkdir -p src/styles && seq 1 20 > src/styles/input.css
{ echo "/* @generated by the styles build */"; seq 1 50; } > src/styles/bundle.css
seq 1 50 > src/styles/output.css; seq 1 50 > src/styles/vendor.css
printf "src/styles/output.css linguist-generated\nsrc/styles/vendor.css linguist-generated=true\n" > .gitattributes
sed -i 1d README.md'
CAP=19 both_modes "$R" generated "$GEN" 'want|src/styles/ holds 20 lines'
CAP=100 both_modes "$R" generated2 "$GEN" 'none|src/styles/'
# Both groups at once: a heading each, fix-now first, and exit 1.
CAP=30 both_modes "$R" two-groups 'seq 1 40 > src/auth/big.js' \
    'rc=1|' 'want|Fix now:' 'want|For the person:' 'want|deletes nothing'
CAP=30 hy "$R" two-groups
[ "$(printf '%s\n' "$out" | grep -n 'Fix now:' | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -n 'For the person:' | cut -d: -f1)" ] \
    && ok "fix-now prints before the person's group" || bad "fix-now should come first: $out"
printf '%s\n' "$out" | grep -q '^- This change deletes nothing' && printf '%s\n' "$out" | grep -q '^  Do: ' \
    && ok "a finding is a list item with its Do line indented" || bad "a finding should render as a list item: $out"

echo "== hygiene: an issue the change added or edited (check 12) =="
both_modes "$R" issue-bare 'mkdir -p docs/issues && printf "# A bug\nIt breaks.\n" > docs/issues/a-bug.md; sed -i 1d README.md' \
    'rc=1|' 'want|docs/issues/a-bug.md has no Type: line.'
both_modes "$R" issue-no-wait 'mkdir -p docs/issues && printf "# A bug\n\nType: bug\n" > docs/issues/a-bug.md; sed -i 1d README.md' \
    'rc=1|' 'want|docs/issues/a-bug.md has no Waits on: line.'
both_modes "$R" issue-unknown 'mkdir -p docs/issues && printf "# A bug\n\nType: defect\nWaits on: nothing\n" > docs/issues/a-bug.md; sed -i 1d README.md' \
    'rc=1|' 'want|docs/issues/a-bug.md has an unknown Type: defect.'
both_modes "$R" issue-fine 'mkdir -p docs/issues && printf "# A bet\n\nType: assumption\nWaits on: evidence\nGated: x\n" > docs/issues/a-bet.md; sed -i 1d README.md' \
    'rc=0|' 'none|docs/issues'

echo "== hygiene: exit 2 =="
out=$(cd "$R" && bash "$WSH" hygiene 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "no change name exits 2" || bad "no change should exit 2 (got $rc)"
hy "$R" no-such-change
[ "$rc" -eq 2 ] && has 'branch hone/no-such-change does not exist' && ok "no such branch exits 2 and says so" || bad "no such branch should exit 2: $rc $out"
out=$(cd "$TMP" && mkdir -p plain && cd plain && bash "$WSH" hygiene x 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "not a repository exits 2" || bad "not a repo should exit 2 (got $rc)"

echo
echo "== attention: nothing on a clean repository =="
A="$TMP/a1"; mkrepo "$A"
rm -f "$A/docs/notes/old.md"
attn "$A"
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "a clean repository prints nothing, exit 0" || bad "a clean repo should be silent (rc $rc): $out"
out=$(cd "$TMP/plain" && bash "$WSH" attention 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "attention outside a repository exits 2" || bad "attention outside a repo should exit 2 (got $rc)"

echo "== attention: Plans (check 1) =="
echo "# Plan" > "$A/.plans/ghost.md"
attn "$A"
[ "$rc" -eq 1 ] && ok "a printed item exits 1" || bad "attention with an item should exit 1 (got $rc)"
has 'ghost.md' && bad "a pending Plan is counted, not named: $out" || ok "a pending Plan is not named"
has '1 Plan(s) wait in .plans/' && ok "pending Plans show as one count" || bad "should count one pending Plan: $out"
[ "$(printf '%s\n' "$out" | grep -c '^- ')" = "$(printf '%s\n' "$out" | wc -l)" ] && ok "each item is one line" || bad "every line should be one item: $out"
# A Plan's reference is not a Plan.
mkdir -p "$A/.plans/ghost"; echo "| in | out |" > "$A/.plans/ghost/cases.md"
attn "$A"; has '1 Plan(s) wait' && ok "a Plan's reference is not counted" || bad "a reference should not count: $out"
rm -rf "$A/.plans/ghost"
# Evidence 1: land's merge commit.
git -C "$A" commit -q --allow-empty -m "Merge branch 'hone/ghost'"
attn "$A"; has '.plans/ghost.md survived its landing (its landing merge commit is in history). Delete the Plan.' \
    && ok "a Plan whose merge commit is in history is named" || bad "should name the landed Plan: $out"
rm -f "$A/.plans/ghost.md"
# Evidence 2: a merged branch that carried a commit of its own.
echo "# Plan" > "$A/.plans/ghost2.md"
git -C "$A" checkout -q -b hone/ghost2 && git -C "$A" commit -q --allow-empty -m "feat: its own"
git -C "$A" checkout -q main && git -C "$A" merge -q --no-ff -m "chore: fold ghost2 in" hone/ghost2
attn "$A"; has '.plans/ghost2.md survived its landing (branch hone/ghost2 is fully merged)' \
    && ok "a Plan whose merged branch carried work is named" || bad "should name ghost2: $out"
git -C "$A" branch -q -D hone/ghost2; rm -f "$A/.plans/ghost2.md"
# A fresh branch carried nothing of its own: no landing, the Plan is pending.
echo "# Plan" > "$A/.plans/ghost4.md"
git -C "$A" branch hone/ghost4 HEAD
attn "$A"
has 'ghost4.md survived' && bad "a fresh branch is no landing: $out" || ok "a fresh branch is no evidence of a landing"
has '1 Plan(s) wait' && ok "its Plan counts as pending" || bad "ghost4 should count as pending: $out"
git -C "$A" branch -q -D hone/ghost4; rm -f "$A/.plans/ghost4.md"
# Nested slug, and a live worktree that keeps a landed-looking Plan quiet.
mkdir -p "$A/.plans/auth"; echo "# Plan" > "$A/.plans/auth/nested.md"
git -C "$A" commit -q --allow-empty -m "Merge branch 'hone/auth/nested'"
attn "$A"; has '.plans/auth/nested.md survived its landing' && ok "a nested landed Plan is named" || bad "should name the nested Plan: $out"
mkdir -p "$A/.worktrees/auth/nested"
attn "$A"; has 'nested' && bad "a Plan with a worktree is active work: $out" || ok "a Plan with a worktree is not named"
rm -rf "$A/.worktrees/auth" "$A/.plans/auth"
# From inside a run's worktree, the run's own Plan is active work, even after
# the run commits (its branch is merged into itself and carries work).
echo "# Plan" > "$A/.plans/ghost3.md"; (cd "$A" && git add .plans/ghost3.md && git commit -qm "plan ghost3")
(cd "$A" && bash "$WSH" add ghost3 >/dev/null 2>&1)
(cd "$A/.worktrees/ghost3" && git commit -q --allow-empty -m "feat: in flight")
attn "$A/.worktrees/ghost3"
has 'ghost3.md survived' && bad "a run's own branch is no landing: $out" || ok "attention from a run's worktree does not read its branch as landed"
git -C "$A" worktree remove --force "$A/.worktrees/ghost3"; git -C "$A" branch -q -D hone/ghost3
(cd "$A" && git rm -q .plans/ghost3.md && git commit -qm "drop ghost3")

echo "== attention: the coordinator rule (check 1) =="
mkdir -p "$A/.plans"; echo "# Plan" > "$A/.plans/d.md"
ST="$A/.git/hone-coordinate"; mkdir -p "$ST/sessions"
printf 'change=a\nagent=run-a\nowner=main1\n' > "$ST/sessions/run-a"
attn "$A"; has 'Plan(s) wait' && bad "a watching coordinator hides the count: $out" || ok "no count while a coordinator watches a session"
rm -f "$ST/sessions/run-a"; echo 7 > "$ST/cursor.main2"
attn "$A" --session main2; has 'Plan(s) wait' && bad "the coordinator's own session hides the count: $out" || ok "no count for a session that waited as a coordinator"
echo 999999 > "$ST/wait.other.pid"
attn "$A" --session p2; has '1 Plan(s) wait' && ok "a stale cursor and a dead wait are no coordinator" || bad "the count should show: $out"
sleep 30 & live=$!
echo "$live" > "$ST/wait.live.pid"
attn "$A"; has 'Plan(s) wait' && bad "a live wait hides the count: $out" || ok "no count while a wait is alive"
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null
rm -rf "$ST" "$A/.plans/d.md"

echo "== attention: merged branches and stale claims (checks 5 and 10) =="
git -C "$A" branch hone/landed-ghost HEAD
(cd "$A" && bash "$WSH" add live >/dev/null 2>&1)
attn "$A"
has "Branch hone/landed-ghost is merged and has no worktree. Delete it with 'git branch -d hone/landed-ghost'." \
    && ok "a merged branch with no worktree is named" || bad "should name hone/landed-ghost: $out"
has 'hone/live' && bad "a branch with a live worktree is active: $out" || ok "a branch with a worktree is not named"
git -C "$A" branch -q -d hone/landed-ghost
empty_commit() { git -C "$A" commit-tree "$(git -C "$A" hash-object -t tree /dev/null)" -m "$1"; }
git -C "$A" update-ref refs/hone/claim/ghost-claim "$(empty_commit 'hone claim: ghost-claim')"
git -C "$A" update-ref refs/hone/claim/live "$(empty_commit 'hone claim: live')"
git -C "$A" update-ref refs/hone/remote-claim/other-dev "$(empty_commit 'hone claim: other-dev')"
attn "$A"
has 'claim on ghost-claim with no worktree' && ok "a stale claim is named" || bad "should name the stale claim: $out"
has "worktree.sh\" release ghost-claim" && ok "the line names the release command" || bad "should name release: $out"
has 'claim on live' && bad "a claim with a worktree is live: $out" || ok "a claim with a worktree is not named"
has 'other-dev' && bad "the team's fetched claims are not this clone's: $out" || ok "the team's claims are not named"
git -C "$A" update-ref -d refs/hone/claim/ghost-claim; git -C "$A" update-ref -d refs/hone/claim/live
git -C "$A" update-ref -d refs/hone/remote-claim/other-dev
git -C "$A" worktree remove --force "$A/.worktrees/live"; git -C "$A" branch -q -D hone/live

echo "== attention: project memory in the harness store (check 7) =="
MEMCFG="$TMP/memcfg"
MEMDIR="$MEMCFG/projects/$(cd "$A" && pwd -P | tr '/' '-')/memory"
mkdir -p "$MEMDIR"
printf -- '---\nname: goal\nmetadata:\n  type: project\n---\n\nship it\n' > "$MEMDIR/goal.md"
printf -- '---\nname: pref\nmetadata:\n  type: user\n---\n\nplain english\n' > "$MEMDIR/pref.md"
out=$(cd "$A" && CLAUDE_CONFIG_DIR="$MEMCFG" bash "$WSH" attention 2>&1)
has "goal.md in" && has "is a 'type: project' harness memory" && ok "a project memory is named" || bad "should name goal.md: $out"
has 'pref.md' && bad "a user memory is the person's own: $out" || ok "a user memory is not named"
out=$(cd "$A" && CLAUDE_CONFIG_DIR="$TMP/none" bash "$WSH" attention 2>&1)
has 'harness memory' && bad "an absent store should yield nothing: $out" || ok "an absent memory store fails open"
attn "$A"; [ -z "$out" ] && ok "the repository is clean again" || bad "leftover attention items: $out"

echo "== attention: issues (checks 12 and 13) =="
mkdir -p "$A/docs/issues"
printf '# Should a viewer see the strip?\n\nType: feature\nWaits on: owner\n' > "$A/docs/issues/viewer-strip.md"
printf '# A bet\n\nType: assumption\nWaits on: evidence\n' > "$A/docs/issues/a-bet.md"
printf '# Old question\n' > "$A/docs/issues/old-one.md"
printf '# Other\n\nType: bug\nWaits on: someone\n' > "$A/docs/issues/other.md"
attn "$A"
[ "$rc" -eq 1 ] && has 'docs/issues/viewer-strip.md waits on your decision: Should a viewer see the strip?' \
    && ok "an issue that waits on the owner is named, with its title" || bad "should name the owner's issue: $out"
has 'a-bet.md' && bad "a bet is not the person's: $out" || ok "an issue that waits on evidence is not named"
has '2 issue(s) in docs/issues/ lack a valid Type: or Waits on: line' \
    && ok "issues without valid fields are counted on one line" || bad "should count two issues without fields: $out"
rm -rf "$A/docs/issues"
attn "$A"; [ -z "$out" ] && ok "the repository is clean again" || bad "leftover attention items: $out"

echo
echo "== session-start: attention reaches both readers, in the primary tree only =="
ss_raw() { (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$SESSION_START" </dev/null); }
S="$TMP/s1"; mkrepo "$S"
git -C "$S" branch hone/left-behind HEAD
out=$(ss_raw "$S")
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
msg=$(printf '%s' "$out" | jq -r '.systemMessage // empty')
printf '%s\n' "$msg" | grep -qF 'these items in this repository need you:' && printf '%s\n' "$msg" | grep -qF 'hone/left-behind' \
    && ok "the person sees the heading and the item" || bad "systemMessage should carry attention: $out"
printf '%s\n' "$ctx" | grep -qF 'Act on one only when the person asks.' && printf '%s\n' "$ctx" | grep -qF 'hone/left-behind' \
    && ok "the model sees the item, marked as the person's" || bad "additionalContext should carry attention: $out"
printf '%s\n' "$ctx" | grep -q '^# hone workflow' && ok "the rule still reaches the model" || bad "the rule should still be injected"
(cd "$S" && bash "$WSH" add wt >/dev/null 2>&1)
out=$(ss_raw "$S/.worktrees/wt")
printf '%s' "$out" | grep -q 'left-behind' && bad "a linked worktree gets no attention: $out" || ok "a linked worktree gets no attention"
git -C "$S" worktree remove --force "$S/.worktrees/wt"; git -C "$S" branch -q -D hone/wt
# A nested review session gets none either. A stand-in named claude runs the
# hook as its child, the way Claude Code does.
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/bash\nbash "$HOOK" </dev/null\n' > "$BIN/claude"; chmod +x "$BIN/claude"
out=$(cd "$S" && CLAUDE_PROJECT_DIR="$S" HOOK="$SESSION_START" "$BIN/claude" -p "/code-review high the brief")
printf '%s' "$out" | grep -q 'left-behind' && bad "a nested review gets no attention: $out" || ok "a nested review session gets no attention"
git -C "$S" branch -q -D hone/left-behind
out=$(ss_raw "$S")
printf '%s' "$out" | grep -q 'need you' && bad "a clean primary tree has no attention heading: $out" || ok "nothing to show, no heading"
# The payload's session id reaches the coordinator rule.
echo "# Plan" > "$S/.plans/p.md"
mkdir -p "$S/.git/hone-coordinate"; echo 1 > "$S/.git/hone-coordinate/cursor.coord1"
out=$(cd "$S" && printf '{"session_id":"coord1"}' | CLAUDE_PROJECT_DIR="$S" bash "$SESSION_START")
printf '%s' "$out" | grep -q 'Plan(s) wait' && bad "the coordinator's session should not hear the count: $out" || ok "session-start passes the session id to attention"
out=$(cd "$S" && printf '{"session_id":"other"}' | CLAUDE_PROJECT_DIR="$S" bash "$SESSION_START")
printf '%s' "$out" | grep -q '1 Plan(s) wait' && ok "another session hears the count" || bad "another session should hear the count: $out"

echo
echo "== setup: the retired nag's file goes =="
U="$TMP/u1"; mkrepo "$U"
(cd "$U" && bash "$WSH" add wt >/dev/null 2>&1)
echo "s1 123" > "$U/.git/hone-nag-seen"
echo "s2 456" > "$U/.git/worktrees/wt/hone-nag-seen"
out=$(cd "$U" && CLAUDE_PROJECT_DIR="$U" bash "$PLUGIN_ROOT/scripts/setup.sh" 2>&1)
[ ! -e "$U/.git/hone-nag-seen" ] && ok "setup removes <git-dir>/hone-nag-seen" || bad "setup should remove hone-nag-seen"
[ ! -e "$U/.git/worktrees/wt/hone-nag-seen" ] && ok "setup removes a worktree's copy too" || bad "setup should remove the worktree's hone-nag-seen"
has 'hone-nag-seen' && ok "setup says what it removed" || bad "setup should name the removed file: $out"
out=$(cd "$U" && CLAUDE_PROJECT_DIR="$U" bash "$PLUGIN_ROOT/scripts/setup.sh" 2>&1)
has 'hone-nag-seen' && bad "a second setup has nothing to remove: $out" || ok "a second setup is quiet about it"

echo
echo "== hooks.json: no nag =="
[ ! -e "$PLUGIN_ROOT/hooks/nag.sh" ] && ok "hooks/nag.sh is gone" || bad "hooks/nag.sh should be deleted"
jq -e '[.hooks[][].hooks[].command] | map(select(test("nag"))) | length == 0' "$PLUGIN_ROOT/hooks/hooks.json" >/dev/null \
    && ok "hooks.json wires no nag" || bad "hooks.json still wires the nag"
jq -r '.description' "$PLUGIN_ROOT/hooks/hooks.json" | grep -qw nag && bad "the hooks.json description still names the nag" || ok "the description names no nag"

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
