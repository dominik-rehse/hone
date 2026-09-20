# Rebuild the workspace of a decision point, and render its history.
#
# Every case's `scaffold.sh` sets SCENARIO, optionally WORKTREE, and then
# sources this file. `claude plugin eval --scaffold` runs that script as you,
# in the empty workspace, before the resumed session starts. The spike of
# 2026-09-20 proved the order: the runner reads `context.history_file` AFTER
# the scaffold, so rendering the history here is what the session obeys.
#
# Four steps:
#   1. unpack the scenario's seeded tree and make it a git repository, the way
#      the lab does (the seed commit is the run's base)
#   2. create the worktree the recorded session was working in, with hone's
#      own `worktree.sh`
#   3. replay what the session had written by the cut (`files/`, `edits.json`)
#   4. render `history.tmpl.jsonl` with this workspace and this plugin
#
# Step 4 is where property 1 is settled. The plugin directory is the candidate
# under test, so its `skills/run/SKILL.md` is the text the resumed session
# reads. See `lib/history.py`.
set -uo pipefail

HERE=${HERE:?scaffold.sh must set HERE}
SCENARIO=${SCENARIO:?scaffold.sh must set SCENARIO}
WORKTREE=${WORKTREE:-}
EVAL_DIR=$(cd "$HERE/../.." && pwd)     # <plugin>/<eval dir>
PLUG=$(cd "$EVAL_DIR/.." && pwd)
WS=$PWD

fail() { echo "prepare: $*" >&2; exit 1; }

# 1. the seeded tree, as a git repository
TARBALL="$EVAL_DIR/fixtures/$SCENARIO.tar.gz"
[ -f "$TARBALL" ] || fail "no fixture at $TARBALL"
tar -xzf "$TARBALL" -C "$WS" || fail "cannot unpack $TARBALL"
export GIT_AUTHOR_NAME="hone lab" GIT_AUTHOR_EMAIL="lab@example.invalid"
export GIT_COMMITTER_NAME="hone lab" GIT_COMMITTER_EMAIL="lab@example.invalid"
git -C "$WS" init -q -b main || fail "git init"
git -C "$WS" add -A || fail "git add"
git -C "$WS" commit -q -m "chore: seed the fixture" || fail "git commit"

# 1b. what the scenario's seed made outside the tracked tree
# `git archive` of the base commit carries tracked files only. A git hook, a
# second branch, and another run's worktree are not tracked, so the scenario
# that needs one has a script under lib/extras/.
if [ -f "$EVAL_DIR/lib/extras/$SCENARIO.sh" ]; then
    # shellcheck disable=SC1090
    . "$EVAL_DIR/lib/extras/$SCENARIO.sh" || fail "lib/extras/$SCENARIO.sh"
fi

# 2. the worktree the recorded session claimed
if [ -n "$WORKTREE" ]; then
    ( cd "$WS" && bash "$PLUG/scripts/worktree.sh" add "$WORKTREE" ) >/dev/null 2>&1 \
        || fail "worktree.sh add $WORKTREE"
fi

# 3. what the session had written by the cut
if [ -d "$HERE/files" ]; then
    ( shopt -s dotglob; cp -a "$HERE/files/." "$WS/" ) || fail "cannot copy files/"
    rm -f "$WS/edits.json"
fi
if [ -s "$HERE/files/edits.json" ]; then
    python3 - "$HERE/files/edits.json" "$WS" <<'PY' || fail "cannot apply edits.json"
import json, sys, os
edits, ws = json.load(open(sys.argv[1])), sys.argv[2]
for e in edits:
    p = os.path.join(ws, e["path"])
    text = open(p, encoding="utf-8").read()
    text = text.replace(e["old"], e["new"], -1 if e["all"] else 1)
    open(p, "w", encoding="utf-8").write(text)
PY
fi

# 4. the history, with this candidate's skill text and this workspace's paths
python3 "$EVAL_DIR/lib/history.py" render "$HERE/history.tmpl.jsonl" \
    --plugin "$PLUG" --workspace "$WS" --out "$HERE/session.jsonl" --quiet \
    || fail "cannot render the history"
