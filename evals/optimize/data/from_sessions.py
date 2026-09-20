# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Recover every `plan-critic` call from Claude Code session transcripts.

The critic runs as a subagent. The harness stores each subagent run beside
its session, as `<session>/subagents/agent-<id>.jsonl` with a `.meta.json`
that names the agent type. The first user turn of that file is the brief the
critic saw. The last assistant text, or the handback, is its report.

Two brief shapes appear in the corpus. The current shape inlines the Plan
text. An older shape says "read it first" and gives a path, so the critic
read the file itself. This script keeps every `Read` result of the run, so a
later step can inline what the critic read.

Nothing private enters the repository. The transcript roots are arguments,
and the output goes to a directory the caller names.

Usage: from_sessions.py <out.jsonl> <transcript-root> [<transcript-root>...]
"""

import glob
import hashlib
import json
import os
import re
import sys

VERDICTS = ("APPROVE", "REJECT")


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for p in content:
            if isinstance(p, dict) and p.get("type") == "text":
                parts.append(p.get("text", ""))
        return "\n".join(parts)
    return ""


def last_verdict(report):
    hits = re.findall(r"\b(APPROVE|REJECT)\b", report.upper())
    return hits[-1] if hits else ""


def one_run(path):
    """Read one subagent transcript. Return the brief, the reads, the report."""
    brief = ""
    report = ""
    handback = ""
    reads = []
    pending = {}
    model = ""
    first_ts = ""
    for line in open(path, errors="replace"):
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if not first_ts:
            first_ts = rec.get("timestamp", "")
        msg = rec.get("message")
        if not isinstance(msg, dict):
            continue
        if isinstance(msg.get("model"), str):
            model = msg["model"]
        content = msg.get("content")
        if msg.get("role") == "user":
            if not brief:
                brief = text_of(content)
            if isinstance(content, list):
                for p in content:
                    if not isinstance(p, dict) or p.get("type") != "tool_result":
                        continue
                    call = pending.pop(p.get("tool_use_id"), None)
                    if call:
                        body = p.get("content")
                        if isinstance(body, list):
                            body = "\n".join(
                                x.get("text", "")
                                for x in body
                                if isinstance(x, dict)
                            )
                        reads.append({"path": call, "content": str(body)})
        if msg.get("role") == "assistant" and isinstance(content, list):
            for p in content:
                if not isinstance(p, dict):
                    continue
                if p.get("type") == "text" and p.get("text", "").strip():
                    report = p["text"]
                if p.get("type") == "tool_use":
                    if p.get("name") == "Read":
                        target = (p.get("input") or {}).get("file_path", "")
                        pending[p.get("id")] = str(target)
                    if p.get("name") == "SubagentHandback":
                        handback = str((p.get("input") or {}).get("message", ""))
    return {
        "brief": brief,
        "reads": reads,
        "report": handback or report,
        "model": model,
        "ts": first_ts,
    }


def main():
    out_path = sys.argv[1]
    roots = sys.argv[2:]
    seen = set()
    records = []
    for root in roots:
        pattern = os.path.join(root, "**", "subagents", "*.meta.json")
        for meta_path in sorted(glob.glob(pattern, recursive=True)):
            try:
                meta = json.load(open(meta_path))
            except Exception:
                continue
            if "plan-critic" not in str(meta.get("agentType", "")):
                continue
            jsonl = meta_path[: -len(".meta.json")] + ".jsonl"
            if not os.path.exists(jsonl):
                continue
            run = one_run(jsonl)
            if not run["brief"]:
                continue
            key = hashlib.sha256(run["brief"].encode("utf-8")).hexdigest()
            item_id = key[:12]
            if item_id in seen:
                continue
            seen.add(item_id)
            run["id"] = item_id
            run["verdict"] = last_verdict(run["report"])
            run["desc"] = str(meta.get("description", ""))
            run["source"] = os.path.basename(root)
            run["agent_file"] = os.path.basename(jsonl)
            records.append(run)

    records.sort(key=lambda r: (r["ts"], r["id"]))
    with open(out_path, "w", encoding="utf-8") as out:
        for r in records:
            out.write(json.dumps(r) + "\n")

    tally = {}
    for r in records:
        tally[r["verdict"] or "none"] = tally.get(r["verdict"] or "none", 0) + 1
    print(f"plan-critic calls: {len(records)} in {out_path}")
    for verdict, count in sorted(tally.items()):
        print(f"  {verdict}: {count}")


if __name__ == "__main__":
    main()
