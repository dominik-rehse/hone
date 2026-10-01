#!/usr/bin/env python3
"""Split a hone prompt file into named sections, and join them back.

evals/lab/variant.py uses this module to switch a part of the loop off in a
copy of the plugin. It drops or replaces whole sections. This module is the
one place that decides where a section starts and what it is called.

The round trip is the contract. `join_sections(split_text(t))` returns `t`
byte for byte.

Split depth: every ATX heading level, h1 to h6, starts a section. A setext
heading is not a split point. A heading inside a code fence is content.

Naming: a section is named by the slug of its heading text. A repeated slug
gets a numeric suffix in document order, so `output` is followed by
`output-2`. The YAML block is `_frontmatter`. The text between it and the
first heading is `_preamble`.

Fine mode (`fine=True`) cuts each heading section again, into units. A unit
starts at a top-level bullet that opens with a bold label, or at a paragraph
at column zero that opens with a label and a period. A unit is named
`<section>/<label-slug>`, as `what-to-hunt/missing-baseline`. The text after
the last bullet unit, back at the level of the section, is `<section>/_tail`.

The module imports the standard library only.
"""

import re
from typing import Iterable, List, NamedTuple, Sequence

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

