#!/usr/bin/env python3
"""Extract hone's hook events and critic verdicts from Claude Code transcripts.

The field pass in .claude/rules/working-here.md starts here: count across the
whole corpus first, then read the sessions behind the counts. This script only
counts and quotes. Whether a block was right stays a judgment for the reader.

Run: python3 -I evals/field/extract.py [--since DATE] [--summary] DIR...

DIR is a project directory under ~/.claude/projects. Pass the worktree
directories of a repository too, because the runs live there. The script
reads only the top-level *.jsonl files of each DIR.

Output: one JSON object per event on stdout. With --summary, a count table.
Fields of an event:
  ts, session, project, hone (version, or "unknown"), kind, hook, tool,
  input (the command or path the hook judged), text (the hook's message,
  or the critic's verdict line), verdict (critic rows only).
Kinds:
  deny      a PreToolUse hook refused a tool call
  block     a PostToolUse or Stop hook returned a blocking error
  advisory  a hook added a system message or context, and blocked nothing
  pass      the gate reported green, the base to read its blocks against
  critic    a hone critic subagent returned; verdict is "none" when the
            critic gave none, for example when it stopped early
A guard's "ask" leaves no record in the transcript, so no row counts it.
Records repeat across a resumed session's files, so the script counts each
record uuid once. The hone version comes from the plugin cache path that
the session's own text names. A session that names no path reads "unknown".
"""
import argparse
import collections
import glob
import json
import os
import re
import sys

HOOK = re.compile(r"hone ([a-z][a-z-]*)(?: \([a-z]+\))?:")
VERSION = re.compile(r"plugins/cache/hone/hone/(\d+\.\d+\.\d+)/")
DENY = re.compile(r"^(?:PreToolUse:(\w+) hook error: )?(?=hone [a-z])")
PASS = re.compile(r"^hone gate: (green|the full suite already passed)")
VERDICT = re.compile(r"\b(APPROVE|REJECT|CUTS PROPOSED|CLEAN)\b")
TEXT_MAX = 400


def hone_hook(*texts):
    for t in texts:
        m = HOOK.search(t or "")
        if m:
            return m.group(1)
    return None


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict))
    return ""


def short(text):
    text = (text or "").strip()
    return text if len(text) <= TEXT_MAX else text[:TEXT_MAX] + "..."


def tool_input(block):
    inp = block.get("input") or {}
    return inp.get("command") or inp.get("file_path") or inp.get("subagent_type") or ""


def session_version(raw):
    counts = collections.Counter(VERSION.findall(raw))
    return counts.most_common(1)[0][0] if counts else "unknown"


def attachment_event(att):
    kind = att.get("type")
    if kind == "hook_blocking_error":
        err = att.get("blockingError") or {}
        text, command = err.get("blockingError", ""), err.get("command", "")
        return "block", hone_hook(text, command), text
    if kind == "hook_system_message":
        text = att.get("content", "")
        return ("pass" if PASS.match(text) else "advisory"), hone_hook(text), text
    if kind == "hook_additional_context":
        content = att.get("content")
        text = "\n".join(c for c in content if isinstance(c, str)) if isinstance(content, list) else str(content or "")
        return "advisory", hone_hook(text), text
    return None


def read_session(path, seen, since):
    """Return (hone version, whether any record is on or after since, events)."""
    with open(path, encoding="utf-8", errors="replace") as f:
        raw = f.read()
    base = {
        "session": os.path.splitext(os.path.basename(path))[0],
        "project": os.path.basename(os.path.dirname(path)),
        "hone": session_version(raw),
    }
    state = {"active": False}
    events = list(session_events(raw, base, seen, since, state))
    events += critic_events(path, base, since)
    return base["hone"], state["active"], events


def session_events(raw, base, seen, since, state):
    uses = {}
    for line in raw.splitlines():
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        ts = rec.get("timestamp", "")
        uid = rec.get("uuid")
        if since and ts and ts < since:
            continue
        if ts:
            state["active"] = True
        if uid and uid in seen:
            continue
        if uid:
            seen.add(uid)
        row = dict(base, ts=ts)
        att = rec.get("attachment")
        if isinstance(att, dict):
            ev = attachment_event(att)
            if ev and ev[1]:
                kind, hook, text = ev
                tool = (att.get("hookName") or "").partition(":")[2]
                yield dict(row, kind=kind, hook=hook, tool=tool, input=uses.get(att.get("toolUseID"), ("", ""))[1], text=short(text))
            continue
        msg = rec.get("message") or {}
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                uses[block.get("id")] = (block.get("name"), tool_input(block))
            elif block.get("type") == "tool_result":
                _, inp = uses.get(block.get("tool_use_id"), ("", ""))
                text = text_of(block.get("content"))
                m = DENY.match(text)
                if block.get("is_error") and m:
                    yield dict(row, kind="deny", hook=hone_hook(text), tool=m.group(1) or uses.get(block.get("tool_use_id"), ("", ""))[0], input=short(inp), text=short(text[m.end():]))


def critic_output(path):
    """Every text the subagent wrote or handed back, in order, and its last timestamp.
    A critic can hand back its report and then end on a short line such as
    "Report delivered.", so the verdict is the last one anywhere in the output."""
    texts, ts = [], ""
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            ts = rec.get("timestamp") or ts
            if rec.get("type") != "assistant":
                continue
            for block in (rec.get("message") or {}).get("content") or []:
                if block.get("type") == "text":
                    texts.append(block.get("text", ""))
                elif block.get("type") == "tool_use" and block.get("name") == "SubagentHandback":
                    texts.extend(v for v in (block.get("input") or {}).values() if isinstance(v, str))
    return "\n".join(texts), ts


def critic_events(session_path, base, since):
    """A critic runs as a subagent, often in the background. Its verdict is
    in its own transcript, beside a .meta.json that names its type."""
    sub = os.path.join(os.path.splitext(session_path)[0], "subagents")
    for meta_path in sorted(glob.glob(os.path.join(sub, "agent-*.meta.json"))):
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
        agent = meta.get("agentType") or ""
        if not agent.startswith("hone:"):
            continue
        text, ts = critic_output(meta_path[: -len(".meta.json")] + ".jsonl")
        if since and ts < since:
            continue
        lines = [ln for ln in text.splitlines() if VERDICT.search(ln)]
        verdict = VERDICT.findall(lines[-1])[-1] if lines else "none"
        yield dict(base, ts=ts, kind="critic", hook=agent.partition(":")[2], tool="Agent", input="", text=short(lines[-1] if lines else ""), verdict=verdict)


def summarize(events, sessions):
    out = []
    out.append(f"sessions read: {len(sessions)}")
    by_version = collections.Counter(sessions.values())
    out.append("sessions by hone version: " + ", ".join(f"{v} {n}" for v, n in sorted(by_version.items())))
    out.append("")
    table = collections.Counter((e["hook"], e["kind"]) for e in events if e["kind"] != "critic")
    hooks = sorted({h for h, _ in table})
    kinds = ["deny", "block", "advisory", "pass"]
    out.append("hook".ljust(16) + "".join(k.rjust(10) for k in kinds) + "  sessions")
    for h in hooks:
        n_sess = len({e["session"] for e in events if e["hook"] == h and e["kind"] != "critic"})
        out.append(h.ljust(16) + "".join(str(table[(h, k)]).rjust(10) for k in kinds) + str(n_sess).rjust(10))
    critics = collections.Counter((e["hook"], e["verdict"]) for e in events if e["kind"] == "critic")
    if critics:
        out.append("")
        out.append("critic verdicts:")
        for (c, v), n in sorted(critics.items()):
            out.append(f"  {c} {v} {n}")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dirs", nargs="+", help="project directories under ~/.claude/projects")
    ap.add_argument("--since", default="", help="ISO date; skip records before it")
    ap.add_argument("--summary", action="store_true", help="print a count table instead of events")
    args = ap.parse_args()
    seen, events, sessions = set(), [], {}
    for d in args.dirs:
        if not os.path.isdir(d):
            sys.exit(f"extract.py: {d} is not a directory. Pass a project directory under ~/.claude/projects.")
        for path in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            version, active, found = read_session(path, seen, args.since)
            if active:
                sessions[os.path.splitext(os.path.basename(path))[0]] = version
            events.extend(found)
    if args.summary:
        print(summarize(events, sessions))
    else:
        for e in events:
            print(json.dumps(e, ensure_ascii=False))


if __name__ == "__main__":
    main()
