#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Turn a recorded lab session into a decision-point history, and back.

Tier 2 of HANDOFF.md resumes a recorded `/hone:run` session just before a
decision, through `context.history_file` of `claude plugin eval`. Two jobs
live here.

`extract` reads the session log that a lab sandbox kept, cuts it just before
a decision, and writes a TEMPLATE. `render` turns a template back into a
session log that the runner can resume.

WHY A TEMPLATE, AND NOT THE LOG ITSELF. Three reasons.

1. Property 1. The skill's text was loaded into the history when the session
   first ran `/hone:run`. A resumed session reads it from there, and never
   from the plugin directory. So a candidate wording in the plugin alone
   changes nothing. The template holds the placeholder `@@HONE_SKILL_RUN@@`
   where the skill's body was, and `render` fills it from the candidate
   plugin. The candidate text is then what the resumed session obeys.
   `docs/spikes/2026-09-20-decision-point-cases.md` has the proof.
2. The paths. A lab session ran under `/var/tmp/hone-lab/<run>/<scenario>/`.
   The eval runner gives each run a fresh workspace with a random path. The
   template holds `@@HONE_WORKSPACE@@` and `@@HONE_PLUGIN@@`, and the case's
   scaffold renders them with the paths of the moment.
3. The size. A recorded session is 200 to 800 KB, and most of it is chatter
   that the runner rebuilds by itself: the token reminders, the budget lines,
   the skill listing, the prompt snapshot. `extract` keeps the turns and the
   hook denials, and drops the rest.

THE SKILL MESSAGE. Claude Code loads a skill as one user message with
`isMeta`. Its text is `Base directory for this skill: <plugin>/skills/<name>`,
a blank line, and then SKILL.md without its frontmatter. Two substitutions
happen in that body: `${CLAUDE_PLUGIN_ROOT}` becomes the plugin directory,
and `$ARGUMENTS` becomes the command's arguments. `skill_message` is that
rule, and `test/decision_points_test.sh` pins it.

Usage:
  history.py extract SESSION.jsonl --upto N --out TEMPLATE.jsonl
                     [--scenario NAME] [--point NAME]
  history.py render TEMPLATE.jsonl --plugin DIR --workspace DIR --out FILE
  history.py show SESSION.jsonl [--from N] [--to N]
  history.py scrub-check FILE...
"""

import argparse
import json
import os
import re
import sys

PLUGIN = "@@HONE_PLUGIN@@"
WORKSPACE = "@@HONE_WORKSPACE@@"
SKILL = "@@HONE_SKILL_RUN@@"
META = "hone-dp-meta"

# Row types worth keeping. `user` and `assistant` are the conversation.
# A blocking hook error and a hook system message are what the model saw when
# a gate or a guard refused it, so they carry the decision's context.
KEEP_TYPES = {"user", "assistant"}
KEEP_ATTACHMENTS = {"hook_blocking_error", "hook_system_message"}

# A line that must never reach the repository. The lab hands the sandbox an
# OAuth token in the environment, and an agent that prints its environment
# writes the token into the log.
SECRETS = [
    re.compile(r"sk-ant-[A-Za-z0-9_\-]{8,}"),
    re.compile(r"ey[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}"),
    re.compile(r"/home/[a-z][a-z0-9_-]*/"),
]


def strip_frontmatter(text):
    """SKILL.md without its YAML frontmatter, as Claude Code loads it."""
    return re.sub(r"\A---\n.*?\n---\n", "", text, count=1, flags=re.S).lstrip("\n")


def skill_message(plugin_root, skill_name, args, skill_md_text):
    """The exact text of the user message that loads a skill."""
    body = strip_frontmatter(skill_md_text)
    body = body.replace("${CLAUDE_PLUGIN_ROOT}", plugin_root)
    body = body.replace("$ARGUMENTS", args)
    head = "Base directory for this skill: %s/skills/%s" % (plugin_root, skill_name)
    return head + "\n\n" + body


def walk_strings(obj, fn):
    """Apply fn to every string in a nested structure."""
    if isinstance(obj, str):
        return fn(obj)
    if isinstance(obj, list):
        return [walk_strings(x, fn) for x in obj]
    if isinstance(obj, dict):
        return {k: walk_strings(v, fn) for k, v in obj.items()}
    return obj


def read_rows(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def row_kind(row):
    t = row.get("type")
    if t == "attachment":
        return "attachment:" + (row.get("attachment") or {}).get("type", "?")
    return t


def is_skill_row(row):
    if row.get("type") != "user" or not row.get("isMeta"):
        return False
    content = (row.get("message") or {}).get("content")
    if isinstance(content, list) and content and content[0].get("type") == "text":
        return content[0]["text"].startswith("Base directory for this skill:")
    return False


def keep(row):
    t = row.get("type")
    if t in KEEP_TYPES:
        return True
    if t == "attachment":
        return (row.get("attachment") or {}).get("type") in KEEP_ATTACHMENTS
    return False


def summarize(row):
    """One short line per row, for `show`."""
    kind = row_kind(row)
    msg = row.get("message") or {}
    content = msg.get("content")
    if content is None:
        text = json.dumps(row.get("attachment") or {})[:160]
        return "%s %s" % (kind, text)
    if isinstance(content, str):
        return "%s text %r" % (kind, content[:160])
    parts = []
    for block in content:
        bt = block.get("type")
        if bt == "text":
            parts.append("text %r" % block.get("text", "")[:160])
        elif bt == "thinking":
            parts.append("thinking")
        elif bt == "tool_use":
            parts.append(
                "tool_use %s %s"
                % (block.get("name"), json.dumps(block.get("input", {}))[:160])
            )
        elif bt == "tool_result":
            body = block.get("content")
            body = body if isinstance(body, str) else json.dumps(body)
            parts.append("tool_result %r" % body[:160])
        else:
            parts.append(str(bt))
    return "%s %s" % (kind, " | ".join(parts))


def find_paths(rows):
    """The plugin directory, the skill name, and the workspace."""
    plugin = skill = None
    for row in rows:
        if is_skill_row(row):
            text = row["message"]["content"][0]["text"].split("\n", 1)[0]
            base = text.split(": ", 1)[1].strip()
            plugin, skill = base.rsplit("/skills/", 1)
            break
    workspace = None
    for row in rows:
        if row.get("cwd"):
            workspace = row["cwd"]
            break
    return plugin, skill, workspace


def find_args(rows):
    for row in rows:
        content = (row.get("message") or {}).get("content")
        text = None
        if isinstance(content, str):
            text = content
        elif isinstance(content, list) and content and content[0].get("type") == "text":
            text = content[0].get("text", "")
        if text and "<command-args>" in text:
            return text.split("<command-args>", 1)[1].split("</command-args>", 1)[0]
    return ""


def extract(args):
    rows = read_rows(args.session)
    plugin, skill_name, workspace = find_paths(rows)
    plugin = args.plugin_root or plugin
    workspace = args.workspace or workspace
    if not plugin or not workspace:
        sys.exit(
            "extract: %s has no skill message or no cwd. A session that never "
            "loaded a skill needs --plugin-root and --workspace." % args.session
        )
    cmd_args = find_args(rows)

    kept = [r for r in rows if keep(r)]
    if args.upto is not None:
        kept = kept[: args.upto]
    # After the cut, never before it, so that the index a `show --kept`
    # listing prints is the index that `--upto` takes.
    kept = [r for r in (drop_thinking(r) for r in kept) if r is not None]
    if not kept:
        sys.exit("extract: nothing kept")

    # The last kept row must be a completed turn, never a tool_use with no
    # result. A dangling tool_use makes the resumed session answer the tool
    # and not the decision.
    while kept and dangling_tool_use(kept):
        kept.pop()
    if not kept:
        sys.exit("extract: every kept row was a dangling tool call")

    # Re-link the chain that the dropped rows broke.
    previous = None
    for row in kept:
        row["parentUuid"] = previous
        if row.get("uuid"):
            previous = row["uuid"]

    user_re = re.compile(r"\b%s\b" % re.escape(args.scrub_user)) if args.scrub_user else None

    def tokenize(text):
        text = text.replace(plugin, PLUGIN)
        text = text.replace(workspace, WORKSPACE)
        if user_re:
            text = user_re.sub("runner", text)
        return text

    out_rows = []
    for row in kept:
        if is_skill_row(row):
            row = walk_strings(row, tokenize)
            # The placeholder stands for the WHOLE message, base-directory
            # line included, because `skill_message` writes that line too.
            row["message"]["content"] = [{"type": "text", "text": SKILL}]
            out_rows.append(row)
            continue
        out_rows.append(walk_strings(row, tokenize))

    meta = {
        "type": META,
        "scenario": args.scenario or "",
        "point": args.point or "",
        "args": cmd_args,
        "skill": skill_name or "",
        "source": os.path.basename(args.session),
        "rows": len(out_rows),
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(meta) + "\n")
        for row in out_rows:
            fh.write(json.dumps(row) + "\n")
    bad = scrub_findings(args.out)
    if bad:
        sys.exit("extract: %s still holds %s" % (args.out, bad))
    print("%s: %d rows, %d bytes" % (args.out, len(out_rows), os.path.getsize(args.out)))


def drop_thinking(row):
    """The row without its thinking blocks, or None when nothing is left.

    Extended thinking of an earlier turn is not part of what a resumed session
    needs, and it was a third of the bytes of the first suite. Dropping it
    shortens every run's input, which is most of what a run costs.
    """
    content = (row.get("message") or {}).get("content")
    if not isinstance(content, list):
        return row
    blocks = [b for b in content if b.get("type") not in ("thinking", "redacted_thinking")]
    if len(blocks) == len(content):
        return row
    if not blocks:
        return None
    row = dict(row)
    row["message"] = dict(row["message"])
    row["message"]["content"] = blocks
    return row


def overlay(args):
    """The files the recorded session had written by the cut, replayed.

    The scaffold rebuilds the workspace from the scenario's seeded tree, which
    is the state before the run started. Whatever the run wrote after that has
    to come back. This replays the `Write` and `Edit` calls up to the cut.

    A `Bash` command that changed the tree is NOT replayed, and the case's
    `prepare.sh` handles the two that matter: `worktree.sh add`, and `git rm`.
    """
    rows = read_rows(args.session)
    plugin, _skill, workspace = find_paths(rows)
    kept = [r for r in rows if keep(r)]
    if args.upto is not None:
        kept = kept[: args.upto]
    files = {}
    edits = []
    order = []
    for row in kept:
        content = (row.get("message") or {}).get("content")
        if row.get("type") != "assistant" or not isinstance(content, list):
            continue
        for block in content:
            if block.get("type") != "tool_use":
                continue
            name = block.get("name")
            data = block.get("input") or {}
            path = data.get("file_path")
            if not path or not path.startswith(workspace + "/"):
                continue
            rel = path[len(workspace) + 1 :]
            if name == "Write":
                if rel not in files:
                    order.append(rel)
                files[rel] = data.get("content", "")
            elif name == "Edit":
                old, new = data.get("old_string", ""), data.get("new_string", "")
                if rel in files:
                    count = -1 if data.get("replace_all") else 1
                    files[rel] = files[rel].replace(old, new, count)
                else:
                    edits.append(
                        {
                            "path": rel,
                            "old": old,
                            "new": new,
                            "all": bool(data.get("replace_all")),
                        }
                    )
    os.makedirs(args.out, exist_ok=True)
    for rel in order:
        dest = os.path.join(args.out, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "w", encoding="utf-8") as fh:
            fh.write(files[rel])
    with open(os.path.join(args.out, "edits.json"), "w", encoding="utf-8") as fh:
        json.dump(edits, fh, indent=1)
    print("overlay: %d file(s), %d edit(s) to seeded files" % (len(order), len(edits)))


def dangling_tool_use(kept):
    """True when the last row asks for a tool that no later row answers."""
    last = kept[-1]
    if last.get("type") != "assistant":
        return False
    content = (last.get("message") or {}).get("content")
    if not isinstance(content, list):
        return False
    return any(b.get("type") == "tool_use" for b in content)


def render(args):
    rows = read_rows(args.template)
    if not rows or rows[0].get("type") != META:
        sys.exit("render: %s has no %s line" % (args.template, META))
    meta = rows[0]
    body = ""
    if meta["skill"]:
        skill_md = os.path.join(args.plugin, "skills", meta["skill"], "SKILL.md")
        if not os.path.exists(skill_md):
            sys.exit("render: no skill at %s" % skill_md)
        with open(skill_md, encoding="utf-8") as fh:
            body = skill_message(args.plugin, meta["skill"], meta["args"], fh.read())

    def fill(text):
        text = text.replace(SKILL, body)
        text = text.replace(PLUGIN, args.plugin)
        text = text.replace(WORKSPACE, args.workspace)
        return text

    with open(args.out, "w", encoding="utf-8") as fh:
        for row in rows[1:]:
            fh.write(json.dumps(walk_strings(row, fill)) + "\n")
    if not args.quiet:
        print("%s: %d rows" % (args.out, len(rows) - 1))


def scrub_findings(path):
    found = []
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    for pattern in SECRETS:
        hit = pattern.search(text)
        if hit:
            found.append(hit.group(0)[:24])
    return found


def scrub_check(args):
    rc = 0
    for path in args.files:
        bad = scrub_findings(path)
        if bad:
            print("%s: %s" % (path, bad))
            rc = 1
    if rc == 0:
        print("scrub-check: %d file(s) clean" % len(args.files))
    return rc


def show(args):
    rows = read_rows(args.session)
    if rows and rows[0].get("type") == META:
        rows = rows[1:]
    if args.kept:
        rows = [r for r in rows if keep(r)]
    for i, row in enumerate(rows):
        if i < args.start:
            continue
        if args.end is not None and i >= args.end:
            break
        print("%4d %s" % (i, summarize(row)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("extract")
    p.add_argument("session")
    p.add_argument("--upto", type=int, default=None, help="keep this many kept rows")
    p.add_argument("--out", required=True)
    p.add_argument("--scenario", default="")
    p.add_argument("--point", default="")
    p.add_argument(
        "--scrub-user",
        default=os.environ.get("USER", ""),
        help="a name to replace with `runner`, so no account name lands in the repo",
    )
    p.add_argument("--plugin-root", default="", help="for a session that loaded no skill")
    p.add_argument("--workspace", default="", help="for a session that loaded no skill")
    p.set_defaults(fn=extract)

    p = sub.add_parser("overlay")
    p.add_argument("session")
    p.add_argument("--upto", type=int, default=None)
    p.add_argument("--out", required=True, help="a directory for the replayed files")
    p.set_defaults(fn=overlay)

    p = sub.add_parser("render")
    p.add_argument("template")
    p.add_argument("--plugin", required=True)
    p.add_argument("--workspace", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--quiet", action="store_true")
    p.set_defaults(fn=render)

    p = sub.add_parser("show")
    p.add_argument("session")
    p.add_argument("--start", type=int, default=0)
    p.add_argument("--end", type=int, default=None)
    p.add_argument("--kept", action="store_true", help="only the rows extract keeps")
    p.set_defaults(fn=show)

    p = sub.add_parser("scrub-check")
    p.add_argument("files", nargs="+")
    p.set_defaults(fn=scrub_check)

    args = parser.parse_args()
    sys.exit(args.fn(args) or 0)


if __name__ == "__main__":
    main()
