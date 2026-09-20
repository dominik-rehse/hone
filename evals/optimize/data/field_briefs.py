# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Turn recovered `plan-critic` calls into labeled, self-contained briefs.

Two shapes of brief appear in the corpus. The current one inlines the Plan
text. An older one names the Plan's path and tells the critic to read it.
`evals/run.sh` calls the critic with no tools, so a brief that names a path
is unanswerable there. This script inlines the Plan text that the critic
read, under one fixed heading, and leaves everything else verbatim.

THE LABEL. It starts as the production verdict. A corrections file then
overrides a verdict that hindsight reversed, and records why. The file is
an argument, so no judgment of a private run sits in this repository. Its
shape:

    {"<agent-file>": {"verdict": "REJECT", "category": "...",
                      "reason": "...", "strength": "solid"}}

PAIRS. Several calls on one Plan are one chain: a rejected draft, then its
revision. The chain is the most valuable item in the set, so the index
links it, and the splitter keeps a chain whole.

Usage: field_briefs.py <calls.jsonl> <out_dir> [--corrections FILE]
"""

import json
import pathlib
import re
import sys

PLAN_HEADING = "\n\n## The Plan under review\n\n"


def strip_line_numbers(text):
    """Undo the `<n>\\t<line>` prefix that the Read tool adds."""
    lines = text.splitlines()
    out = []
    for line in lines:
        match = re.match(r"^\s*\d+\t(.*)$", line)
        out.append(match.group(1) if match else line)
    return "\n".join(out)


def plan_slug(record):
    match = re.search(r"\.plans/([\w\-/]+)\.md", record["brief"])
    if match:
        return match.group(1)
    match = re.search(r"#+ Plan: ([\w\-/]+)", record["brief"])
    return match.group(1) if match else record["id"]


# A heading line, not a mention. An early version matched `## What to weigh`,
# which is a heading of the brief itself and not of the Plan.
PLAN_MARK = re.compile(r"^(#{1,4} Plan:|#{2,4} What\s*$)", re.MULTILINE)


def has_inline_plan(brief):
    return bool(PLAN_MARK.search(brief))


def inline_plan(record, slug):
    """Find the Read result that holds the Plan named in the brief."""
    tail = slug.split("/")[-1] + ".md"
    for read in record["reads"]:
        if read["path"].endswith(tail) and ".plans/" in read["path"]:
            return strip_line_numbers(read["content"])
    return ""


def inline_references(record, slug, brief):
    """Append every reference under `.plans/<slug>/` that the critic read.

    A reference carries the data the Plan deliberately does not restate. A
    brief that only names one is unanswerable with no tools, so the offline
    call rejects for a file it cannot open. Measured on 2026-09-20.
    """
    added = 0
    for read in record["reads"]:
        path = read["path"]
        if ".plans/" not in path or path.endswith(slug + ".md"):
            continue
        name = ".plans/" + path.split(".plans/")[-1]
        if name in brief and "\n## Reference `" + name not in brief:
            body = strip_line_numbers(read["content"]).strip()
            if body:
                brief += f"\n\n## Reference `{name}`\n\n{body}\n"
                added += 1
    return brief, added


def build(record):
    slug = plan_slug(record)
    brief = record["brief"].rstrip()
    inlined = False
    if not has_inline_plan(brief):
        body = inline_plan(record, slug)
        if body:
            brief = brief + PLAN_HEADING + body.strip() + "\n"
            inlined = True
    brief, refs = inline_references(record, slug, brief)
    return slug, brief + "\n", inlined, refs


def main():
    args = sys.argv[1:]
    corrections = {}
    if "--corrections" in args:
        i = args.index("--corrections")
        corrections = json.load(open(args[i + 1]))
        del args[i : i + 2]
    src, out = args[0], pathlib.Path(args[1])

    records = [json.loads(line) for line in open(src, encoding="utf-8")]
    chains = {}
    items = []
    dropped = 0

    for record in records:
        if record["verdict"] not in ("APPROVE", "REJECT"):
            dropped += 1
            continue
        slug, brief, inlined, refs = build(record)
        if not has_inline_plan(brief):
            dropped += 1
            continue
        fix = corrections.get(record["agent_file"], {})
        label = fix.get("verdict", record["verdict"])
        item = {
            "id": record["id"],
            "chain": slug,
            "label": label,
            "production_verdict": record["verdict"],
            "category": fix.get("category", ""),
            "label_source": (
                "hindsight: " + fix.get("reason", "")
                if fix
                else "production verdict, no correction reported"
            ),
            "label_strength": fix.get("strength", "production"),
            "brief_shape": "plan inlined by this script" if inlined else "verbatim",
            "references_inlined": refs,
            "ts": record["ts"],
            "words": len(brief.split()),
            "origin": "field",
        }
        chains.setdefault(slug, []).append(item)
        items.append(item)

    for slug, group in chains.items():
        group.sort(key=lambda i: i["ts"])
        for position, item in enumerate(group):
            item["chain_length"] = len(group)
            item["chain_position"] = position

    for record in records:
        if record["verdict"] not in ("APPROVE", "REJECT"):
            continue
        slug, brief, _, _ = build(record)
        if not has_inline_plan(brief):
            continue
        case = out / record["id"]
        case.mkdir(parents=True, exist_ok=True)
        (case / "brief.md").write_text(brief, encoding="utf-8")
        item = next(i for i in items if i["id"] == record["id"])
        (case / "expected").write_text(item["label"] + "\n", encoding="utf-8")
        (case / "report.txt").write_text(record["report"], encoding="utf-8")

    (out / "index.json").write_text(
        json.dumps({"items": items}, indent=2) + "\n", encoding="utf-8"
    )

    approve = sum(1 for i in items if i["label"] == "APPROVE")
    reject = sum(1 for i in items if i["label"] == "REJECT")
    paired = sum(1 for i in items if i["chain_length"] > 1)
    flipped = sum(1 for i in items if i["label"] != i["production_verdict"])
    print(f"briefs: {len(items)} in {out} ({dropped} dropped, no usable Plan)")
    print(f"  APPROVE {approve}, REJECT {reject}")
    print(f"  chains longer than one: {len(set(i['chain'] for i in items if i['chain_length'] > 1))}")
    print(f"  items in such a chain: {paired}")
    print(f"  labels corrected by hindsight: {flipped}")


if __name__ == "__main__":
    main()
