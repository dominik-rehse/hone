# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Assemble the `plan-critic` set and split it into three parts.

It merges two sources. The field part is a brief a real run handed the
critic. The generated part is that brief with one defect injected against
one bullet. Each case gets a fixed preface, because the offline call has no
file tools and says so in its reply unless it is told not to. The probe
behind that preface is in the note under `docs/spikes/`.

TWO THINGS STAY TOGETHER, so that a split leaks nothing.

  * A chain. Several calls on one Plan are a rejected draft and its
    revision, and the two share almost all their text.
  * A source and its mutations. A mutation differs from its source in one
    anchor, so a source in train and its mutation in held out would be a
    leak.

The two rules join, so the unit of the split is a group. Every group that
holds a case built from hone's own visible cases goes to validation, per
HANDOFF.md.

Usage: split.py <field_dir> <generated_dir> <out_dir> --preface FILE [--seed N]
"""

import argparse
import json
import pathlib
import random
import shutil

TRAIN, VALIDATION = 0.60, 0.20


def group_of(item, field_chain):
    if item["origin"] == "field":
        return "chain:" + item["chain"]
    source = item["source_id"]
    if source.startswith("hone-"):
        return "hone"
    return "chain:" + field_chain.get(source, source)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("field")
    ap.add_argument("generated")
    ap.add_argument("out")
    ap.add_argument("--preface", required=True)
    ap.add_argument("--seed", type=int, default=20260920)
    args = ap.parse_args()

    field = pathlib.Path(args.field)
    generated = pathlib.Path(args.generated)
    out = pathlib.Path(args.out)
    preface = pathlib.Path(args.preface).read_text(encoding="utf-8").rstrip() + "\n\n---\n\n"

    field_items = json.load(open(field / "index.json"))["items"]
    gen_items = json.load(open(generated / "index.json"))["items"]
    field_chain = {i["id"]: i["chain"] for i in field_items}

    items = []
    for item in field_items:
        item["dir"] = str(field / item["id"])
        items.append(item)
    for item in gen_items:
        item["dir"] = str(generated / item["id"])
        items.append(item)
    for item in items:
        item["group"] = group_of(item, field_chain)

    groups = sorted({i["group"] for i in items})
    forced = sorted({i["group"] for i in items if i["group"] == "hone"})
    free = [g for g in groups if g not in forced]
    random.Random(args.seed).shuffle(free)

    count = len(free)
    part_of = {g: "validation" for g in forced}
    for n, g in enumerate(free):
        if n < int(count * TRAIN):
            part_of[g] = "train"
        elif n < int(count * (TRAIN + VALIDATION)):
            part_of[g] = "validation"
        else:
            part_of[g] = "holdout"

    cases = out / "cases"
    shutil.rmtree(cases, ignore_errors=True)
    cases.mkdir(parents=True, exist_ok=True)
    parts = {"train": [], "validation": [], "holdout": []}
    for item in items:
        item["part"] = part_of[item["group"]]
        case = cases / item["id"]
        case.mkdir(parents=True, exist_ok=True)
        brief = pathlib.Path(item["dir"], "brief.md").read_text(encoding="utf-8")
        (case / "brief.md").write_text(preface + brief, encoding="utf-8")
        (case / "expected").write_text(item["label"] + "\n", encoding="utf-8")
        parts[item["part"]].append(item["id"])
        item.pop("dir")

    out.mkdir(parents=True, exist_ok=True)
    for part, ids in parts.items():
        (out / f"{part}.ids").write_text("\n".join(sorted(ids)) + "\n", encoding="utf-8")
    (out / "index.json").write_text(
        json.dumps({"seed": args.seed, "items": items}, indent=2) + "\n",
        encoding="utf-8")

    print(f"cases: {len(items)} in {cases}")
    for part in ("train", "validation", "holdout"):
        chosen = [i for i in items if i["part"] == part]
        approve = sum(1 for i in chosen if i["label"] == "APPROVE")
        field_n = sum(1 for i in chosen if i["origin"] == "field")
        print(f"  {part:11}: {len(chosen):4}  "
              f"({approve} APPROVE, {len(chosen) - approve} REJECT; "
              f"{field_n} field, {len(chosen) - field_n} generated)")
    print(f"groups: {len(groups)}")


if __name__ == "__main__":
    main()
