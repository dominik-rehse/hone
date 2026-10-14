#!/bin/bash
# Cases for evals/field/extract.py, the reader that counts hone's hook events
# and critic verdicts in Claude Code transcripts. The fixture holds one record
# per shape the transcripts use, plus the shapes the reader must skip.
# Run: bash test/field_extract_test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXTRACT="$ROOT/evals/field/extract.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0

check() { # check <name> <want> <got>
    if [ "$2" = "$3" ]; then pass=$((pass+1)); else
        fail=$((fail+1)); printf '  FAIL %s: want "%s", got "%s"\n' "$1" "$2" "$3"; fi
}

P="$T/proj"; mkdir -p "$P/s1/subagents"
cat > "$P/s1.jsonl" <<'EOF'
{"type":"user","uuid":"u0","timestamp":"2026-10-01T00:00:00Z","message":{"content":"run /home/x/.claude/plugins/cache/hone/hone/0.79.1/scripts/worktree.sh"}}
{"type":"assistant","uuid":"u1","timestamp":"2026-10-10T00:00:00Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"git commit -m x"}}]}}
{"type":"user","uuid":"u2","timestamp":"2026-10-10T00:00:01Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"PreToolUse:Bash hook error: hone bash-guard: this command would disable the hone gate."}]}}
{"type":"assistant","uuid":"u3","timestamp":"2026-10-10T00:00:02Z","message":{"content":[{"type":"tool_use","id":"t2","name":"Write","input":{"file_path":"docs/a.md"}}]}}
{"type":"user","uuid":"u4","timestamp":"2026-10-10T00:00:03Z","message":{"content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"hone guard: docs/a.md is a protected path in the primary tree."}]}}
{"type":"attachment","uuid":"u5","timestamp":"2026-10-10T00:00:04Z","attachment":{"type":"hook_blocking_error","hookName":"Stop","blockingError":{"blockingError":"hone gate: lint failed with exit 1.","command":"x"}}}
{"type":"attachment","uuid":"u6","timestamp":"2026-10-10T00:00:05Z","attachment":{"type":"hook_system_message","content":"hone gate: green (tests (--unit), lint)"}}
{"type":"attachment","uuid":"u7","timestamp":"2026-10-10T00:00:06Z","attachment":{"type":"hook_system_message","content":"hone nag (advisory): 1 finding(s), unchanged since the last stop."}}
{"type":"attachment","uuid":"u8","timestamp":"2026-10-10T00:00:07Z","attachment":{"type":"hook_blocking_error","hookName":"PostToolUse:Edit","blockingError":{"blockingError":"ste lint found 1 problem(s)","command":"ste: checking prose..."}}}
{"type":"user","uuid":"u9","timestamp":"2026-10-10T00:00:08Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"Exit code 1\nhone worktree: no such change"}]}}
{"type":"attachment","uuid":"old","timestamp":"2026-09-01T00:00:00Z","attachment":{"type":"hook_system_message","content":"hone nag (advisory): old"}}
not json
EOF
# A resumed session repeats a record; the reader counts it once.
sed -n 6p "$P/s1.jsonl" > "$P/s2.jsonl"
printf '{"agentType":"hone:plan-critic"}\n' > "$P/s1/subagents/agent-a.meta.json"
cat > "$P/s1/subagents/agent-a.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-10-10T00:01:00Z","message":{"content":[{"type":"text","text":"I will APPROVE only a Plan that names its baseline."}]}}
{"type":"assistant","timestamp":"2026-10-10T00:02:00Z","message":{"content":[{"type":"tool_use","name":"SubagentHandback","input":{"report":"1. missing-baseline: no baseline.\n\nVerdict: REJECT"}}]}}
{"type":"assistant","timestamp":"2026-10-10T00:03:00Z","message":{"content":[{"type":"text","text":"Report delivered."}]}}
EOF
printf '{"agentType":"general-purpose"}\n' > "$P/s1/subagents/agent-b.meta.json"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"APPROVE"}]}}\n' > "$P/s1/subagents/agent-b.jsonl"

out=$(python3 -I "$EXTRACT" --since 2026-10-02 "$P")
field() { printf '%s\n' "$out" | python3 -I -c '
import json,sys
kind,key=sys.argv[1],sys.argv[2]
print(",".join(str(json.loads(l).get(key)) for l in sys.stdin if json.loads(l)["kind"]==kind))' "$1" "$2"; }

check deny-hooks "bash-guard,guard" "$(field deny hook)"
check deny-tools "Bash,Write" "$(field deny tool)"
check deny-input "git commit -m x,docs/a.md" "$(field deny input)"
check block-once "gate" "$(field block hook)"
check pass "gate" "$(field pass hook)"
check advisory-since "nag" "$(field advisory hook)"
check critic "plan-critic:REJECT" "$(field critic hook):$(field critic verdict)"
check version "0.79.1" "$(printf '%s\n' "$out" | head -n 1 | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["hone"])')"
check rows "6" "$(printf '%s\n' "$out" | grep -c .)"

summary=$(python3 -I "$EXTRACT" --since 2026-10-02 --summary "$P")
check summary-sessions "sessions read: 2" "$(printf '%s\n' "$summary" | head -n 1)"
check summary-critic "  plan-critic REJECT 1" "$(printf '%s\n' "$summary" | tail -n 1)"

python3 -I "$EXTRACT" "$T/missing" >/dev/null 2>&1
check not-a-dir "1" "$?"

echo "field_extract_test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
