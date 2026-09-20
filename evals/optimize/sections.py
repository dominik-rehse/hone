#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Split a hone prompt file into named sections, and join them back.

A search over hone's prose edits one part at a time. A whole skill of 4,700
words is too large for one rewrite, so the unit is a section. This script is
the one place that decides where a section starts and what it is called. Two
callers use it:

  * GEPA (step 6 of HANDOFF.md) reads a candidate as a dict of name to text.
    `to_candidate` and `from_candidate` are that conversion.
  * The variant script (step 5) removes whole sections from a copy of the
    plugin. `drop` on the command line is that operation.

THE ROUND TRIP IS THE CONTRACT. `join(split(f))` returns `f` byte for byte,
for every shipped prompt file. `test/optimize_test.sh` proves it. A split
that is not exact would make every later diff unreadable.

SPLIT DEPTH: every ATX heading level, h1 to h6, starts a section. Two reasons
for the full depth. Step 5 switches off single steps of the loop, and those
are `###` headings in `skills/run/SKILL.md`. And a split at `##` alone would
leave one section of about 2,000 words in `skills/plan/SKILL.md`, which is
what the section unit exists to avoid. A setext heading (an underline of `=`
or `-`) is not a split point, because no shipped file uses one.

NAMING: a section is named by the slug of its heading text. The slug is
lower case, and every run of other characters becomes one hyphen. A repeated
slug gets a numeric suffix in document order, so `output` is followed by
`output-2`. Two sections carry no heading and get a reserved name that
starts with an underscore: `_frontmatter` is the YAML block, and `_preamble`
is the text between it and the first heading. `to_candidate` leaves both out
by default, because a search must not rewrite frontmatter.

FINE MODE (`--fine`, or `fine=True`) cuts each heading section again, into
units. A critic needs it. The section ablation of 2026-09-18 cut a top-level
bullet, and step 6 locks or frees a unit of that size, such as *Missing
baseline* or *Calibration* (see
docs/spikes/2026-09-18-section-ablation-on-opus.md). `evals/run.sh` itself
names no section. It takes a whole file through `--prompt-file`, and the
copy with a section deleted was made by hand. Fine mode is off by default,
because a skill is edited at heading level.

The rule for one heading section, in order:

  * A *bullet unit* starts at a top-level bullet that opens with a bold
    label: `- **Missing baseline.** Does the Plan ...`. A label that ends in
    a colon counts too. An indented bullet is continuation, not a unit.
  * A *paragraph unit* starts at column zero, after a blank line, with a
    label and a period. The label is one capitalized word of three letters
    or more, as `Calibration. A REJECT must ...`, or a short bold label that
    ends in a period. The pattern is tight, because an ordinary sentence
    opens with a word and a space.
  * A unit runs to the next unit, or to the end of the section. A bullet
    unit also ends at the first line that returns to the level of the
    section: column zero, after a blank line, and not a bullet. That
    remainder is `<section>/_tail`, and a second one is `_tail-2`. A
    paragraph unit has no tail, because its own continuation sits at column
    zero as well.
  * The text before the first unit keeps the section's own name.
  * A unit is named `<section>/<label-slug>`, as
    `what-to-hunt/missing-baseline`.

Headings, bullets, and labels inside a fenced code block are content in both
modes. The round trip holds in fine mode too.

Usage:
  python3 evals/optimize/sections.py split FILE [--fine] [-o OUT.json]
  python3 evals/optimize/sections.py names FILE [--fine]
  python3 evals/optimize/sections.py join MANIFEST.json [-o OUT]
  python3 evals/optimize/sections.py drop FILE -s NAME [-s NAME] [--fine] \
      [-o OUT|-i]
  python3 evals/optimize/sections.py replace FILE -s NAME --with TEXT_FILE \
      [--fine] [-o OUT|-i]

`drop` and `replace` need `--fine` to see a unit name. Every subcommand
writes to stdout without `-o`. `-i` edits FILE in place. The script runs
under `uv run` and under plain `python3`. It imports the standard library
only, so it needs no environment and no install.

Module API:
  split_text(text, fine=False) -> [Section(name, text)]
  split_file(path, fine=False) -> [Section]
  join_sections(sections) -> text                read_file / write_file
  to_candidate(sections) -> {name: text}         from_candidate(sections, d)
  drop_sections(sections, names)                 replace_section(s, name, t)
"""

import argparse
import json
import re
import sys
from typing import Dict, Iterable, List, NamedTuple, Sequence

# An ATX heading: up to three leading spaces, one to six hashes, then a space
# or the end of the line. Four leading spaces make an indented code block, so
# the limit of three is what CommonMark says.
HEADING = re.compile(r"^ {0,3}(#{1,6})(?:[ \t].*)?$")
# A code fence: three or more backticks or tildes, with an optional info
# string. A heading inside a fence is content, not a split point.
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
DASHES = re.compile(r"^---[ \t]*$")
# Fine mode. A top-level bullet that opens with a bold label is a unit: the
# shape of every hunt bullet in the two critics.
BULLET_LABEL = re.compile(r"^[-*+][ \t]+\*\*(?P<label>[^*\n]{1,60}?)\*\*")
# A paragraph that opens with a label and a period, at column zero. Either one
# capitalized word of three letters or more, or a short bold label. The
# pattern is tight on purpose: an ordinary sentence opens with a word and a
# space, not with a word and a period.
LABEL_PARA = re.compile(
    r"^(?:\*\*(?P<bold>[A-Z][^*\n]{2,40}?)\.\*\*|(?P<plain>[A-Z][A-Za-z]{2,19})\.)[ \t]"
)
# A line that returns to the level of the section: column zero, and not a
# bullet of any kind.
BULLET_ANY = re.compile(r"^(?:[-*+][ \t]|\d+[.)][ \t])")


class Section(NamedTuple):
    """One named part of a prompt file. `text` holds the exact bytes."""

    name: str
    text: str


def _lines(text: str) -> List[str]:
    """Split on newlines only, and keep every terminator.

    `str.splitlines` also breaks on a form feed and on other unicode line
    marks. That would put a split point where no markdown reader sees a line.
    A CRLF file keeps its `\\r` at the end of the line content, so the join
    returns it unchanged.
    """
    parts = text.split("\n")
    out = [p + "\n" for p in parts[:-1]]
    if parts[-1]:
        out.append(parts[-1])
    return out


def _bare(line: str) -> str:
    """The line without its terminator, and without a CR before it."""
    return line.rstrip("\n").rstrip("\r")


def heading_title(line: str) -> str:
    """The text of an ATX heading, without its hashes."""
    t = _bare(line).strip()
    t = re.sub(r"^#{1,6}[ \t]*", "", t)
    t = re.sub(r"[ \t]+#+[ \t]*$", "", t)
    return t.strip()


def slugify(title: str) -> str:
    """A stable name for a heading. Only the heading text decides it."""
    s = re.sub(r"[`*_~'’]", "", title.lower())
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "section"


def _unique(names: Sequence[str]) -> List[str]:
    """Give every name a distinct form, in document order.

    A repeat gets the next free numeric suffix. The loop also covers the case
    where the suffixed name is itself a heading in the file.
    """
    used = set()
    out = []
    for base in names:
        candidate = base
        n = 1
        while candidate in used:
            n += 1
            candidate = "%s-%d" % (base, n)
        used.add(candidate)
        out.append(candidate)
    return out


def _unit_cuts(lines: Sequence[str]) -> List["tuple"]:
    """Find the units inside one heading section. See the module header.

    Returns a list of (index, name) for every unit start. Line 0 is the
    heading, so it never starts a unit.
    """
    cuts = []
    fence = None
    kind = None
    prev_blank = True
    for j in range(1, len(lines)):
        raw = _bare(lines[j])
        fenced = FENCE.match(raw)
        if fenced:
            marker, rest = fenced.group(1), fenced.group(2)
            if fence is None:
                fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence) and not rest.strip():
                fence = None
            prev_blank = False
            continue
        if fence is not None:
            prev_blank = False
            continue
        if not raw.strip():
            prev_blank = True
            continue
        bullet = BULLET_LABEL.match(raw)
        para = LABEL_PARA.match(raw) if prev_blank else None
        if bullet:
            cuts.append((j, slugify(bullet.group("label"))))
            kind = "bullet"
        elif para:
            cuts.append((j, slugify(para.group("bold") or para.group("plain"))))
            kind = "para"
        elif kind == "bullet" and prev_blank and not BULLET_ANY.match(raw) and raw[0] not in " \t":
            cuts.append((j, "_tail"))
            kind = "tail"
        prev_blank = False
    return cuts


def _split_section(section: Section) -> List[Section]:
    """Cut one heading section into its units, or return it unchanged."""
    lines = _lines(section.text)
    cuts = _unit_cuts(lines)
    if not cuts:
        return [section]
    out = [Section(section.name, "".join(lines[: cuts[0][0]]))]
    for k, (start, label) in enumerate(cuts):
        end = cuts[k + 1][0] if k + 1 < len(cuts) else len(lines)
        out.append(Section("%s/%s" % (section.name, label), "".join(lines[start:end])))
    return out


def split_text(text: str, fine: bool = False) -> List[Section]:
    """Split one prompt file into sections. See the module header."""
    lines = _lines(text)

    # The YAML frontmatter, when the file opens with a fence of three dashes.
    # Without a closing fence there is no frontmatter, and the text goes into
    # the preamble.
    fm_end = 0
    if lines and DASHES.match(_bare(lines[0])):
        for j in range(1, len(lines)):
            if DASHES.match(_bare(lines[j])):
                fm_end = j + 1
                break

    # The heading lines, skipping every line inside a code fence.
    cuts = []
    fence = None
    for j in range(fm_end, len(lines)):
        raw = _bare(lines[j])
        fenced = FENCE.match(raw)
        if fenced:
            marker, rest = fenced.group(1), fenced.group(2)
            if fence is None:
                fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence) and not rest.strip():
                fence = None
            continue
        if fence is None and HEADING.match(raw):
            cuts.append(j)

    bounds = []
    if fm_end:
        bounds.append(("_frontmatter", 0, fm_end))
    first = cuts[0] if cuts else len(lines)
    if first > fm_end:
        bounds.append(("_preamble", fm_end, first))
    for k, start in enumerate(cuts):
        end = cuts[k + 1] if k + 1 < len(cuts) else len(lines)
        bounds.append((slugify(heading_title(lines[start])), start, end))

    parts = [Section(b[0], "".join(lines[b[1]:b[2]])) for b in bounds]
    if fine:
        cut = []
        for part in parts:
            # The frontmatter and the preamble carry no heading, so they hold
            # no unit either.
            cut.extend([part] if part.name.startswith("_") else _split_section(part))
        parts = cut
    names = _unique([p.name for p in parts])
    return [Section(name, part.text) for name, part in zip(names, parts)]


def join_sections(sections: Iterable[Section]) -> str:
    """Put the sections back together. The inverse of `split_text`."""
    return "".join(s.text for s in sections)


def read_file(path: str) -> str:
    """Read a file as text. An undecodable byte survives as a surrogate."""
    with open(path, "rb") as fh:
        return fh.read().decode("utf-8", "surrogateescape")


def write_file(path: str, text: str) -> None:
    with open(path, "wb") as fh:
        fh.write(text.encode("utf-8", "surrogateescape"))


def split_file(path: str, fine: bool = False) -> List[Section]:
    return split_text(read_file(path), fine=fine)


def to_candidate(sections: Iterable[Section], include_meta: bool = False) -> Dict[str, str]:
    """The dict form a search optimizes. Frontmatter stays out by default."""
    return {
        s.name: s.text
        for s in sections
        if include_meta or not s.name.startswith("_")
    }


def from_candidate(sections: Iterable[Section], candidate: Dict[str, str]) -> List[Section]:
    """Apply a candidate dict, keeping the order and the untouched parts."""
    return [Section(s.name, candidate.get(s.name, s.text)) for s in sections]


def _check_names(sections: Sequence[Section], names: Iterable[str]) -> None:
    known = {s.name for s in sections}
    for name in names:
        if name not in known:
            raise KeyError(name)


def drop_sections(sections: Sequence[Section], names: Iterable[str]) -> List[Section]:
    """Remove whole sections by name. Every other byte stays as it was."""
    wanted = list(names)
    _check_names(sections, wanted)
    return [s for s in sections if s.name not in set(wanted)]


def replace_section(sections: Sequence[Section], name: str, text: str) -> List[Section]:
    """Swap the text of one section. The heading is part of that text."""
    _check_names(sections, [name])
    return [Section(s.name, text if s.name == name else s.text) for s in sections]


def to_manifest(path: str, sections: Iterable[Section]) -> Dict:
    return {"path": path, "sections": [{"name": s.name, "text": s.text} for s in sections]}


def from_manifest(obj: Dict) -> List[Section]:
    return [Section(s["name"], s["text"]) for s in obj["sections"]]


def _emit(text: str, out: str) -> None:
    if out:
        write_file(out, text)
    else:
        sys.stdout.buffer.write(text.encode("utf-8", "surrogateescape"))


def _target(args) -> str:
    return args.file if getattr(args, "in_place", False) else args.out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Split a hone prompt file into named sections.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    fine_help = "also cut each section into its labelled bullets and paragraphs"

    p = sub.add_parser("split", help="write the sections of FILE as a JSON manifest")
    p.add_argument("file")
    p.add_argument("-o", "--out", default="")
    p.add_argument("--fine", action="store_true", help=fine_help)

    p = sub.add_parser("names", help="print one section name per line")
    p.add_argument("file")
    p.add_argument("--fine", action="store_true", help=fine_help)

    p = sub.add_parser("join", help="rebuild the file a manifest describes")
    p.add_argument("manifest")
    p.add_argument("-o", "--out", default="")

    p = sub.add_parser("drop", help="remove one or more named sections from FILE")
    p.add_argument("file")
    p.add_argument("-s", "--section", action="append", default=[], required=True)
    p.add_argument("-o", "--out", default="")
    p.add_argument("-i", "--in-place", action="store_true")
    p.add_argument("--fine", action="store_true", help=fine_help)

    p = sub.add_parser("replace", help="swap the text of one named section of FILE")
    p.add_argument("file")
    p.add_argument("-s", "--section", required=True)
    p.add_argument("--with", dest="with_file", required=True, help="file holding the new text")
    p.add_argument("-o", "--out", default="")
    p.add_argument("-i", "--in-place", action="store_true")
    p.add_argument("--fine", action="store_true", help=fine_help)

    args = ap.parse_args(argv)

    try:
        if args.cmd == "join":
            with open(args.manifest, "rb") as fh:
                obj = json.loads(fh.read().decode("utf-8", "surrogateescape"))
            _emit(join_sections(from_manifest(obj)), args.out)
            return 0

        sections = split_file(args.file, fine=args.fine)
        if args.cmd == "split":
            # ensure_ascii keeps a surrogate readable as an escape, so the
            # manifest is plain ASCII whatever the file holds.
            _emit(json.dumps(to_manifest(args.file, sections), indent=2) + "\n", args.out)
        elif args.cmd == "names":
            _emit("".join(s.name + "\n" for s in sections), "")
        elif args.cmd == "drop":
            _emit(join_sections(drop_sections(sections, args.section)), _target(args))
        elif args.cmd == "replace":
            text = read_file(args.with_file)
            _emit(join_sections(replace_section(sections, args.section, text)), _target(args))
    except KeyError as exc:
        sys.stderr.write("no such section: %s\n" % exc.args[0])
        return 2
    except (OSError, ValueError) as exc:
        sys.stderr.write("%s\n" % exc)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
