#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Build one variant of hone in a copy of the plugin.

A VARIANT is the list of parts that are off, plus the settings. The parts are
the six hooks, the two critics, five steps of the loop, and the three gates
inside land. `evals/lab/parts.json` is the map: one entry per part, with what
the part is for, what the loop does without it, and every place the part is
written down. This script applies that map. It writes only into the copy that
`evals/lab/run.sh` makes per scenario, and never into this repository.

Four kinds of part, and each goes off in its own way:

  hook    the entry goes out of hooks.json in the copy. The script stays, and
          so does every sentence that names the hook. That is how --without
          has worked since 2026-09-17.
  agent   the agent file goes out of the copy, and every section that calls
          the agent goes with it. An agent that is gone with its call still
          standing would stall the run on a missing subagent.
  step    the sections of skills/run/SKILL.md that hold the step go, and so do
          the sentences elsewhere that name it. A step named after it was
          dropped gives a confused model, not a clean ablation.
  gate    one substitution in the copy of scripts/worktree.sh switches the
          gate off. The gates have no environment switch, and a gate is a
          whole part of the structure layer, so a substitution is the smallest
          honest option. Each one must match its anchor exactly once.

THE ANCHORS ARE CHECKED AGAINST THIS REPOSITORY, always, before a build. A
`sub` that no longer matches its declared count fails the build loudly. So a
reword of a skill or of worktree.sh cannot leave a silent no-op behind.

Prose goes through evals/optimize/sections.py, which is the one place that
decides where a section starts and what it is called.

Usage:
  python3 evals/lab/variant.py --check [SELECTION]      validate, print nothing
  python3 evals/lab/variant.py --json  [SELECTION]      print the resolved variant
  python3 evals/lab/variant.py --parts                  list the parts
  python3 evals/lab/variant.py --plugin DIR [SELECTION] build DIR in place

SELECTION is any mix of:
  --without a,b,c        parts to switch off, by name
  --variant NAME|PATH    a file under evals/lab/variants/, or a path to one:
                         {"off": [...], "settings": {...}}
  --set KEY=VALUE        one setting, e.g. --set review.model=claude-sonnet-5

`--check` with no selection validates every part and every setting of
parts.json, which is what test/lab_test.sh runs. Exit 0 on success, 2 on any
error. The resolved variant is what run.sh writes into result.json, so no run
can be mistaken for the full arm.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
# $LAB_PARTS points the builder at another part map. test/lab_test.sh uses it
# to prove that a stale section name and a stale anchor both fail loudly.
PARTS_FILE = os.environ.get("LAB_PARTS") or os.path.join(HERE, "parts.json")
VARIANT_DIR = os.environ.get("LAB_VARIANTS") or os.path.join(HERE, "variants")

sys.dont_write_bytecode = True   # no __pycache__ beside the splitter or here
sys.path.insert(0, os.path.join(ROOT, "evals", "optimize"))
try:
    import sections  # evals/optimize/sections.py
except ImportError as e:  # pragma: no cover - a missing splitter is a broken repo
    sys.stderr.write("variant: evals/optimize/sections.py is missing (%s)\n" % e)
    raise SystemExit(2)

LEVELS = ("low", "medium", "high", "max")


class Fail(Exception):
    pass


def load_parts():
    with open(PARTS_FILE, encoding="utf-8") as f:
        return json.load(f)


def text_of(value):
    """A `from`, `to` or `with` field: a list of lines, or one string."""
    if isinstance(value, list):
        return "\n".join(value)
    return value


# ---------------------------------------------------------------- resolution

def resolve(spec, without, sets):
    """One variant from a variant file, --without and --set, in that order."""
    off, settings = [], {}
    if spec:
        path = spec if os.path.sep in spec or spec.endswith(".json") else \
            os.path.join(VARIANT_DIR, spec + ".json")
        if not os.path.isfile(path):
            raise Fail("no variant file at %s" % path)
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
        off = list(doc.get("off", []))
        settings = dict(doc.get("settings", {}))
    for name in without:
        name = name.strip()
        if name and name not in off:
            off.append(name)
    for item in sets:
        if "=" not in item:
            raise Fail("--set takes KEY=VALUE, not '%s'" % item)
        key, value = item.split("=", 1)
        settings[key.strip()] = value.strip()
    return {"off": off, "settings": settings}


def check_semantics(parts, variant):
    """Unknown names, and combinations that describe no arm anybody meant."""
    known = parts["parts"]
    off = variant["off"]
    for name in off:
        if name not in known:
            raise Fail("no part named '%s'. Parts: %s" % (name, ", ".join(sorted(known))))
    if len(set(off)) != len(off):
        raise Fail("a part is named twice: %s" % ", ".join(off))
    for name in off:
        entry = known[name]
        for need in entry.get("requires", []):
            if need not in off:
                raise Fail("'%s' off needs '%s' off too: %s" % (name, need, entry["means"]))
        for clash in entry.get("excludes", []):
            if clash in off:
                raise Fail("'%s' and '%s' cannot both be off: %s" % (name, clash, entry["means"]))
    for key, value in variant["settings"].items():
        spec = parts["settings"].get(key)
        if spec is None:
            raise Fail("no setting named '%s'. Settings: %s"
                       % (key, ", ".join(sorted(parts["settings"]))))
        owner = spec.get("part")
        if owner in off:
            raise Fail("'%s' sets a part that is off ('%s')" % (key, owner))
        if key.endswith(".model") and not value.startswith("claude-"):
            raise Fail("'%s' takes a full model ID, and '%s' is an alias" % (key, value))
        if key == "review.level" and value not in LEVELS:
            raise Fail("review.level takes one of %s, not '%s'" % (", ".join(LEVELS), value))
    # A note, not a refusal: the arm is real, and it is easy to misread.
    notes = []
    if "consolidate" in off and "consolidate-critic" not in off:
        notes.append("consolidate is off, so nothing calls the consolidate-critic. "
                     "The agent stays in the copy and never runs.")
    if "review" in off and "gate" in off:
        notes.append("review and gate are both off, so nothing but land reads the change.")
    if "land" in off:
        notes.append(parts["parts"]["land"]["caution"])
    return notes


# ------------------------------------------------------------------- editing

class Edits(object):
    """The edits of one build, over a root of files (the repo, or the copy)."""

    def __init__(self, root, strict):
        self.root = root
        self.strict = strict   # the repo: every count must hold
        self.cache = {}

    def read(self, rel):
        if rel not in self.cache:
            path = os.path.join(self.root, rel)
            if not os.path.isfile(path):
                raise Fail("no file at %s" % rel)
            with open(path, encoding="utf-8") as f:
                self.cache[rel] = f.read()
        return self.cache[rel]

    def write_all(self):
        for rel, text in self.cache.items():
            with open(os.path.join(self.root, rel), "w", encoding="utf-8") as f:
                f.write(text)

    def sub(self, rel, frm, to, count, where):
        text = self.read(rel)
        seen = text.count(frm)
        if self.strict and seen != count:
            raise Fail("%s: the anchor of %s occurs %d time(s) in %s, not %d.\n"
                       "  anchor: %s" % (where, rel, seen, rel, count, frm.split("\n")[0]))
        self.cache[rel] = text.replace(frm, to)

    def drop(self, rel, names, fine, where):
        text = self.read(rel)
        secs = sections.split_text(text, fine=fine)
        have = set(s.name for s in secs)
        missing = [n for n in names if n not in have]
        if missing and self.strict:
            raise Fail("%s: %s has no section named '%s'" % (where, rel, missing[0]))
        # In a copy, another part may have dropped the section already.
        names = [n for n in names if n in have]
        self.cache[rel] = sections.join_sections(sections.drop_sections(secs, names))

    def replace(self, rel, name, body, fine, where):
        text = self.read(rel)
        secs = sections.split_text(text, fine=fine)
        if name not in set(s.name for s in secs):
            if self.strict:
                raise Fail("%s: %s has no section named '%s'" % (where, rel, name))
            return
        self.cache[rel] = sections.join_sections(sections.replace_section(secs, name, body))


def apply_part(edits, name, entry):
    # Drop, then replace, then substitute. A drop after a replace would re-split
    # the file, and the text a replace left could then ride out on a neighbour.
    where = "part '%s'" % name
    for item in entry.get("drop", []):
        edits.drop(item["file"], item["sections"], item.get("fine", False), where)
    for item in entry.get("replace", []):
        edits.replace(item["file"], item["section"], text_of(item["with"]) + "\n",
                      item.get("fine", False), where)
    for item in entry.get("sub", []):
        edits.sub(item["file"], text_of(item["from"]), text_of(item["to"]),
                  item.get("count", 1), where)


def apply_setting(edits, key, spec, value):
    where = "setting '%s'" % key
    rel = spec["file"]
    if spec.get("frontmatter_key"):
        field = spec["frontmatter_key"]
        text = edits.read(rel)
        pat = re.compile(r"^%s: .*$" % re.escape(field), re.M)
        seen = len(pat.findall(text))
        if edits.strict and seen != 1:
            raise Fail("%s: %s carries %d '%s:' line(s), not 1" % (where, rel, seen, field))
        edits.cache[rel] = pat.sub("%s: %s" % (field, value), text, count=1)
        return
    if spec.get("review_pin"):
        # The review command pins one model. The run skill states the pin in
        # one place, and a command with no pin or with two must not build.
        text = edits.read(rel)
        block = re.compile(r"(claude -p \"/code-review(?:.|\n){0,400}?--output-format)")
        found = block.search(text)
        if not found:
            raise Fail("%s: %s has no /code-review command" % (where, rel))
        pins = re.findall(r"--model claude-[A-Za-z0-9.-]+", found.group(1))
        if edits.strict and len(pins) != 1:
            raise Fail("%s: the review command in %s pins %d models, not 1"
                       % (where, rel, len(pins)))
        fixed = re.sub(r"--model claude-[A-Za-z0-9.-]+", "--model " + value, found.group(1))
        edits.cache[rel] = text[:found.start(1)] + fixed + text[found.end(1):]
        return
    for item in spec.get("sub", []):
        # The anchor carries the shipped value; `{value}` in `to` takes the new one.
        edits.sub(rel, text_of(item["from"]), text_of(item["to"]).replace("{value}", value),
                  item.get("count", 1), where)


def build(parts, variant, root):
    """Apply the whole variant to one root, in the order of parts.json."""
    edits = Edits(root, strict=False)
    for name in parts["parts"]:          # a fixed order, so a build is reproducible
        if name in variant["off"]:
            apply_part(edits, name, parts["parts"][name])
    for key in sorted(variant["settings"]):
        apply_setting(edits, key, parts["settings"][key], variant["settings"][key])
    return edits


def touched(parts, variant):
    """Every file of the copy that this variant may change. Nothing else may."""
    paths = set()
    for name in variant["off"]:
        entry = parts["parts"][name]
        if entry.get("hook"):
            paths.add("hooks/hooks.json")
        if entry.get("agent"):
            paths.add(entry["agent"])
        for key in ("drop", "replace", "sub"):
            for item in entry.get(key, []):
                paths.add(item["file"])
    for key in variant["settings"]:
        paths.add(parts["settings"][key]["file"])
    return paths


def validate_anchors(parts, off, settings):
    """Every anchor of every selected part, against THIS repository.

    One part at a time, each against the shipped files. A part that another
    part's drop would have removed is still checked against what hone ships,
    so a reword can never pass unseen.
    """
    for name in off:
        entry = parts["parts"][name]
        if entry.get("hook"):
            wiring = os.path.join(ROOT, "hooks", "hooks.json")
            with open(wiring, encoding="utf-8") as f:
                if "/hooks/%s.sh" % entry["hook"] not in f.read():
                    raise Fail("hooks.json wires no hook named '%s'" % entry["hook"])
        if entry.get("agent") and not os.path.isfile(os.path.join(ROOT, entry["agent"])):
            raise Fail("part '%s' names no file at %s" % (name, entry["agent"]))
        apply_part(Edits(ROOT, strict=True), name, entry)
    for key, value in settings.items():
        apply_setting(Edits(ROOT, strict=True), key, parts["settings"][key], value)


def switch_hooks(plugin, off):
    """Drop the hook entries of every hook part that is off."""
    path = os.path.join(plugin, "hooks", "hooks.json")
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    for name in off:
        needle = "/hooks/%s.sh" % name
        events = {}
        for event, groups in doc.get("hooks", {}).items():
            kept = []
            for group in groups:
                group = dict(group)
                group["hooks"] = [h for h in group.get("hooks", [])
                                  if needle not in h.get("command", "")]
                if group["hooks"]:
                    kept.append(group)
            if kept:
                events[event] = kept
        doc["hooks"] = events
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--plugin", help="the plugin copy to edit in place")
    ap.add_argument("--without", default="", help="parts to switch off, comma separated")
    ap.add_argument("--variant", default="", help="a named variant file, or a path to one")
    ap.add_argument("--set", dest="sets", action="append", default=[], help="KEY=VALUE")
    ap.add_argument("--check", action="store_true", help="validate only")
    ap.add_argument("--json", action="store_true", help="print the resolved variant")
    ap.add_argument("--parts", action="store_true", help="list the parts")
    ap.add_argument("--touches", action="store_true",
                    help="print every file of the copy that the selection may change")
    args = ap.parse_args(argv)

    parts = load_parts()
    if args.parts:
        for name, entry in parts["parts"].items():
            print("%-20s %-7s %s" % (name, entry["kind"], entry["what"]))
        for name, entry in parts["settings"].items():
            print("%-20s %-7s %s" % (name, "setting", entry["what"]))
        return 0

    try:
        names = [n for n in args.without.split(",") if n.strip()]
        variant = resolve(args.variant, names, args.sets)
        # Every part and every setting, when a check names none. That is the
        # sweep test/lab_test.sh runs, and it needs no semantic check: it never
        # builds one copy out of all of them.
        if args.check and not variant["off"] and not variant["settings"] and not args.variant:
            probes = dict((k, "high" if k.endswith(".level") else "claude-probe-0")
                          for k in parts["settings"])
            validate_anchors(parts, list(parts["parts"]), probes)
            return 0
        if args.touches:
            for path in sorted(touched(parts, variant)):
                print(path)
            return 0
        notes = check_semantics(parts, variant)
        # The anchors, against this repository. A build that skipped this could
        # write a copy that still names the part it dropped.
        validate_anchors(parts, variant["off"], variant["settings"])
        for note in notes:
            sys.stderr.write("variant: %s\n" % note)
        if args.json:
            print(json.dumps(variant, sort_keys=True))
        if args.plugin:
            if not os.path.isdir(args.plugin):
                raise Fail("no plugin copy at %s" % args.plugin)
            hooks = [n for n in variant["off"] if parts["parts"][n].get("hook")]
            switch_hooks(args.plugin, hooks)
            for name in variant["off"]:
                agent = parts["parts"][name].get("agent")
                if agent:
                    os.remove(os.path.join(args.plugin, agent))
            build(parts, variant, args.plugin).write_all()
    except Fail as e:
        sys.stderr.write("variant: %s\n" % e)
        return 2
    except KeyError as e:   # an unknown section name, from sections.py
        sys.stderr.write("variant: no section named %s\n" % e)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
