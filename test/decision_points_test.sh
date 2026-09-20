#!/bin/bash
# Mechanical proof of the decision-point suite, tier 2 of HANDOFF.md. It makes
# no model call.
#
# Four claims.
#
#   1. `skill_message` reproduces the user message that Claude Code writes
#      when it loads a skill: the base-directory line, then SKILL.md without
#      its frontmatter, with `${CLAUDE_PLUGIN_ROOT}` and `$ARGUMENTS` filled
#      in. A recorded session holds that message, and step 8 rewrites it with
#      a candidate's text. The whole suite rests on this rule.
#   2. Extract then render returns the recorded rows, and the rendered skill
#      text is the one in the plugin directory that render was given. That is
#      property 1 of the spike, proved without a model.
#   3. Every case is complete: a template, a prompt, a grader, a fixture, and
#      a line in sources.tsv. No template holds an account name or a token.
#   4. `prepare.sh` builds a workspace from a fixture: a git repository at the
#      seed commit, the worktree the recorded session held, the files the
#      session had written, and a session log with this workspace's paths.
#
# Run: bash test/decision_points_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
DP="$PLUGIN_ROOT/evals/decision-points"
HISTORY="$DP/lib/history.py"
export PYTHONDONTWRITEBYTECODE=1

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "== the skill message, and the round trip =="
probe() { python3 - "$HISTORY" "$W" <<'PY'
import importlib.util, json, os, sys, uuid
spec = importlib.util.spec_from_file_location("history", sys.argv[1])
H = importlib.util.module_from_spec(spec)
spec.loader.exec_module(H)
W = sys.argv[2]
plugin = os.path.join(W, "orig")
args = "text/slugify"
os.makedirs(os.path.join(plugin, "skills", "run"), exist_ok=True)

skill = ('---\nname: run\ndescription: "x"\n---\n\n# /hone:run\n\n'
         'Input: $ARGUMENTS\n\nRun `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh`.\n')
msg = H.skill_message(plugin, "run", args, skill)
want = ("Base directory for this skill: %s/skills/run\n\n" % plugin +
        "# /hone:run\n\nInput: text/slugify\n\n"
        "Run `%s/scripts/worktree.sh`.\n" % plugin)
print("SKILL_MESSAGE", "ok" if msg == want else "bad")
print("NO_FRONTMATTER", "ok" if "description:" not in msg else "bad")

# A session log of the shape a lab sandbox keeps, with the chatter that
# extract must drop and a dangling tool call at the end.
def row(u, t, content, **kw):
    d = dict(parentUuid=None, isSidechain=False, type=t, uuid=u,
             timestamp="2026-09-20T09:00:00.000Z", sessionId="s", version="2.1.278",
             cwd="/lab/repo", gitBranch="main")
    if content is not None:
        d["message"] = {"role": "user" if t == "user" else "assistant",
                        "content": content}
    d.update(kw)
    return d

rows = [
    {"type": "queue-operation", "operation": "enqueue", "sessionId": "s"},
    row("u1", "user", [{"type": "text", "text":
        "<command-message>hone:run</command-message>\n<command-name>/hone:run"
        "</command-name>\n<command-args>text/slugify</command-args>"}]),
    row("u2", "user", [{"type": "text", "text": msg}], isMeta=True),
    {"parentUuid": None, "isSidechain": False, "type": "attachment",
     "attachment": {"type": "budget_usd", "content": "x"}, "uuid": "a1"},
    row("a2", "assistant", [{"type": "thinking", "thinking": "hm"},
                            {"type": "text", "text": "Working in /lab/repo now."}]),
    row("a3", "assistant", [{"type": "thinking", "thinking": "only thinking"}]),
    row("a4", "assistant", [{"type": "tool_use", "name": "Write", "id": "t1",
                             "input": {"file_path": "/lab/repo/a.js",
                                       "content": "one\n"}}]),
    row("u3", "user", [{"type": "tool_result", "tool_use_id": "t1",
                        "content": "written by runner"}]),
    row("a5", "assistant", [{"type": "tool_use", "name": "Bash", "id": "t2",
                             "input": {"command": "echo hi"}}]),
]
src = os.path.join(W, "session.jsonl")
with open(src, "w") as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")

class A: pass
a = A()
a.session, a.upto, a.out = src, None, os.path.join(W, "tmpl.jsonl")
a.scenario, a.point, a.scrub_user = "fixture", "p", "runner"
a.plugin_root, a.workspace = "", ""
import io, contextlib
with contextlib.redirect_stdout(io.StringIO()):
    H.extract(a)
tmpl = H.read_rows(a.out)
meta, body = tmpl[0], tmpl[1:]
print("META_SKILL", "ok" if meta["skill"] == "run" and meta["args"] == args else "bad")
print("DROPS_CHATTER", "ok" if len(body) == 5 else "bad %d" % len(body))
print("DROPS_DANGLING", "ok" if body[-1]["type"] == "user" else "bad")
print("RELINKS", "ok" if body[0]["parentUuid"] is None
      and body[1]["parentUuid"] == body[0]["uuid"] else "bad")
print("TOKENIZED", "ok" if H.WORKSPACE in json.dumps(body) and "/lab/repo" not in json.dumps(body) else "bad")
print("SKILL_PLACEHOLDER", "ok" if H.SKILL in json.dumps(body[1]) else "bad")
print("SCRUBBED_USER", "ok" if "runner" in json.dumps(body) else "bad")

# Render with a plugin whose skill carries a marker: the marker must land in
# the history, because that is what the resumed session reads.
os.makedirs(os.path.join(W, "cand", "skills", "run"), exist_ok=True)
with open(os.path.join(W, "cand", "skills", "run", "SKILL.md"), "w") as fh:
    fh.write(skill.replace("# /hone:run", "# /hone:run\n\nMARKER-9Q."))
a2 = A()
a2.template, a2.plugin = a.out, os.path.join(W, "cand")
a2.workspace, a2.out, a2.quiet = "/ws", os.path.join(W, "out.jsonl"), True
H.render(a2)
out = json.dumps(H.read_rows(a2.out))
print("CANDIDATE_TEXT", "ok" if "MARKER-9Q." in out else "bad")
print("RENDER_PATHS", "ok" if "/ws/a.js" in out and H.WORKSPACE not in out else "bad")

# The same render against the original plugin returns the recorded bytes.
with open(os.path.join(plugin, "skills", "run", "SKILL.md"), "w") as fh:
    fh.write(skill)
a2.plugin, a2.workspace, a2.out = plugin, "/lab/repo", os.path.join(W, "back.jsonl")
H.render(a2)
back = H.read_rows(a2.out)
print("ROUND_TRIP", "ok" if back[1]["message"]["content"][0]["text"] == msg else "bad")
print("ROUND_TRIP_ROWS", "ok" if json.dumps(back[3]["message"]) == json.dumps(rows[6]["message"]) else "bad")

# The scrub check has to find a token and a home path.
bad_file = os.path.join(W, "leak.jsonl")
with open(bad_file, "w") as fh:
    fh.write('{"t":"sk-ant-oat01-AAAAAAAAAAAA"}\n{"t":"/home/someone/x"}\n')
print("SCRUB_FINDS", "ok" if len(H.scrub_findings(bad_file)) == 2 else "bad")
print("SCRUB_CLEAN", "ok" if H.scrub_findings(a.out) == [] else "bad")
PY
}
# The block prints one `NAME ok` or `NAME bad` line per claim.
claims=$(probe 2>&1)
if [ -z "$claims" ]; then
    bad "the history.py checks did not run"
else
    while read -r claim verdict rest; do
        case "$verdict" in
            ok) ok "$claim";;
            *) bad "$claim ($verdict $rest)";;
        esac
    done <<<"$claims"
fi

echo "== every case is complete =="
missing=0
while IFS=$'\t' read -r name scenario worktree cut turns sandbox; do
    case "$name" in ''|'#'*) continue;; esac
    d="$DP/cases/$name"
    for f in case.yaml prompt.md history.tmpl.jsonl scaffold.sh; do
        [ -f "$d/$f" ] || { bad "$name has no $f"; missing=$((missing+1)); }
    done
    n=$(ls "$d"/graders/*.md 2>/dev/null | wc -l)
    [ "$n" -ge 1 ] || { bad "$name has no grader"; missing=$((missing+1)); }
    [ -f "$DP/fixtures/$scenario.tar.gz" ] || {
        bad "$name names the scenario $scenario, which has no fixture"
        missing=$((missing+1)); }
    grep -q "^SCENARIO=$scenario\$" "$d/scaffold.sh" 2>/dev/null || {
        bad "$name: scaffold.sh does not name $scenario"; missing=$((missing+1)); }
done < "$DP/sources.tsv"
[ "$missing" -eq 0 ] && ok "every line of sources.tsv has a complete case"

listed=$(grep -cvE '^#|^$' "$DP/sources.tsv")
built=$(find "$DP/cases" -maxdepth 1 -mindepth 1 -type d | wc -l)
[ "$listed" -eq "$built" ] && ok "$built case directories, $listed lines in sources.tsv" \
    || bad "$built case directories against $listed lines in sources.tsv"
[ "$built" -ge 24 ] && ok "the suite has $built cases" \
    || bad "the suite has only $built cases"

python3 "$HISTORY" scrub-check "$DP"/cases/*/history.tmpl.jsonl >/dev/null 2>&1 \
    && ok "no template holds an account name or a token" \
    || bad "a template holds an account name or a token"

holes=0
for f in "$DP"/cases/*/history.tmpl.jsonl; do
    head -1 "$f" | grep -q '"hone-dp-meta"' || { holes=$((holes+1)); bad "$f has no meta line"; }
done
[ "$holes" -eq 0 ] && ok "every template opens with its meta line"

echo "== prepare.sh builds a workspace =="
# A whole plugin copy, as run.sh makes one, so that the scaffold finds
# worktree.sh and the suite beside it.
P="$W/plugin"
mkdir -p "$P/dp"
for d in .claude-plugin agents hooks rules scripts skills templates; do
    cp -r "$PLUGIN_ROOT/$d" "$P/" || bad "cannot copy $d"
done
cp -r "$DP/lib" "$DP/fixtures" "$DP/cases" "$P/dp/"
WS="$W/ws"
mkdir -p "$WS"
( cd "$WS" && bash "$P/dp/cases/build-test-first/scaffold.sh" ) >"$W/prep.log" 2>&1
if [ $? -ne 0 ]; then
    bad "prepare.sh failed: $(tail -2 "$W/prep.log")"
else
    ok "prepare.sh ran"
    [ -d "$WS/.git" ] && ok "it made a git repository" || bad "no .git"
    [ -f "$WS/scripts/run-tests.sh" ] && ok "it unpacked the seeded tree" \
        || bad "no scripts/run-tests.sh in the workspace"
    [ -d "$WS/.worktrees/text/slugify" ] && ok "it created the worktree" \
        || bad "no worktree at .worktrees/text/slugify"
    S="$P/dp/cases/build-test-first/session.jsonl"
    if [ -f "$S" ]; then
        ok "it rendered the session log"
        grep -q "$WS" "$S" && ok "the log carries this workspace's path" \
            || bad "the log does not carry $WS"
        grep -q 'HONE_WORKSPACE\|HONE_SKILL' "$S" \
            && bad "the log still holds a placeholder" \
            || ok "no placeholder survived the render"
        # The shipped skill's text, not the recorded one.
        grep -q 'The three ways to stop' "$S" \
            && ok "the log carries the plugin's own skill text" \
            || bad "the log does not carry the plugin's skill text"
    else
        bad "no session.jsonl rendered"
    fi
fi

echo
echo "decision_points_test.sh: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
