# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Read a `measure.sh` result and report accuracy by label, origin, and bullet.

HANDOFF.md's stop rule needs accuracy per label. Step 6 needs it per bullet,
because a bullet the critic already gets right on every case has no failure
for GEPA to learn from.

Usage: report.py <set_dir> <result.jsonl> [<result.jsonl>...] [--part NAME]
"""

import collections
import json
import pathlib
import sys


def main():
    args = sys.argv[1:]
    part = None
    if "--part" in args:
        i = args.index("--part")
        part = args[i + 1]
        del args[i : i + 2]
    set_dir = pathlib.Path(args[0])
    index = {i["id"]: i for i in json.load(open(set_dir / "index.json"))["items"]}

    rows = []
    for path in args[1:]:
        for line in open(path):
            row = json.loads(line)
            item = index.get(row["case"])
            if not item:
                continue
            if part and item["part"] != part:
                continue
            rows.append((item, row))

    if not rows:
        sys.exit("no rows matched")

    def table(title, key):
        buckets = collections.defaultdict(lambda: [0, 0])
        for item, row in rows:
            bucket = buckets[key(item)]
            bucket[0] += 1
            bucket[1] += 1 if row["pass"] else 0
        print(f"\n{title}")
        for name in sorted(buckets):
            total, right = buckets[name]
            print(f"  {name:36} {right:>4}/{total:<4} {100.0 * right / total:>5.0f}%")

    print(f"cases scored: {len(rows)}" + (f", part {part}" if part else ""))
    table("by label", lambda i: i["label"])
    table("by origin", lambda i: i["origin"])
    table("by bullet", lambda i: i.get("category") or "field brief")

    dead = sum(1 for _, row in rows if not row["verdict"])
    if dead:
        print(f"\nno answer: {dead}")


if __name__ == "__main__":
    main()
