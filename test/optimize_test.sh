#!/bin/bash
# Mechanical proof of evals/optimize/sections.py, the section splitter the
# prose search is built on. Two claims. Split then join returns every shipped
# prompt file byte for byte. And a drop of one named section removes that
# section and no other byte. Both claims hold in fine mode too, where a
# labelled bullet or paragraph of a critic is a unit of its own. Small
# fixtures carry the cases the shipped files do not hold: a heading inside a
# code fence, a repeated heading, a missing trailing newline, CRLF, and a
# file with no heading at all. The test also runs the module API that GEPA
# uses. It makes no model call.
# Run: bash test/optimize_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$PLUGIN_ROOT/evals/optimize/sections.py"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

sec() { python3 "$SCRIPT" "$@"; }

# One round trip: split to a manifest, join the manifest, compare the bytes.
# A second argument passes --fine.
roundtrip() {
    if [ -n "${2:-}" ]; then
        sec split "$1" "$2" -o "$W/m.json" >/dev/null || return 1
    else
        sec split "$1" -o "$W/m.json" >/dev/null || return 1
    fi
    sec join "$W/m.json" -o "$W/back" || return 1
    cmp -s "$1" "$W/back"
}

echo "== round trip: every shipped prompt file =="
FILES=$(cd "$PLUGIN_ROOT" && ls agents/*.md skills/*/SKILL.md skills/run/references/*.md rules/workflow.md)
count=$(printf '%s\n' "$FILES" | wc -l)
[ "$count" -ge 10 ] && ok "the shipped prompt set holds $count files" \
    || bad "expected at least 10 shipped prompt files, found $count"
broken=0
while IFS= read -r rel; do
    roundtrip "$PLUGIN_ROOT/$rel" || { bad "$rel does not survive split and join"; broken=$((broken+1)); }
done <<<"$FILES"
[ "$broken" -eq 0 ] && ok "all $count survive split and join byte for byte"

# A name has to be usable as a key and as an argument, so it must be distinct
# inside its file. Every shipped file also has to split into more than one
# part, or the section unit buys nothing there.
thin=0
while IFS= read -r rel; do
    n=$(sec names "$PLUGIN_ROOT/$rel" | wc -l)
    u=$(sec names "$PLUGIN_ROOT/$rel" | sort -u | wc -l)
    [ "$n" -ge 2 ] || { bad "$rel splits into $n section(s)"; thin=$((thin+1)); }
    [ "$n" -eq "$u" ] || { bad "$rel has a repeated section name"; thin=$((thin+1)); }
done <<<"$FILES"
[ "$thin" -eq 0 ] && ok "every file splits into distinct, named parts"

# A reference has no frontmatter, so it opens with a heading section.
first=$(sec names "$PLUGIN_ROOT/skills/run/references/land.md" | head -1)
[ "$first" = "worktree-sh-land-exit-codes-and-what-each-one-means" ] \
    && ok "a file without frontmatter opens with its heading section" \
    || bad "land.md should open with its heading section (got '$first')"

echo "== fine mode: the critics split into the units the ablation named =="
broken=0
while IFS= read -r rel; do
    roundtrip "$PLUGIN_ROOT/$rel" --fine || { bad "$rel does not round trip in fine mode"; broken=$((broken+1)); }
done <<<"$FILES"
[ "$broken" -eq 0 ] && ok "all $count survive the fine split and join byte for byte"

fine=$(sec names "$PLUGIN_ROOT/agents/plan-critic.md" --fine)
want_units="what-to-hunt/placeholders
what-to-hunt/contradictions
what-to-hunt/ambiguity
what-to-hunt/missing-baseline
what-to-hunt/scope
what-to-hunt/prose-doing-an-artifacts-job
what-to-hunt/collision-with-an-open-change
what-to-hunt/slug-collision
what-to-hunt/contract-churn
output/calibration"
absent=0
while IFS= read -r unit; do
    printf '%s\n' "$fine" | grep -qxF "$unit" || { bad "the fine split of plan-critic has no $unit"; absent=$((absent+1)); }
done <<<"$want_units"
[ "$absent" -eq 0 ] && ok "every unit the 2026-09-18 ablation named has a fine name"
[ "$(printf '%s\n' "$fine" | sort -u | wc -l)" -eq "$(printf '%s\n' "$fine" | wc -l)" ] \
    && ok "the fine names of plan-critic are distinct" || bad "a fine name repeats"

# The consolidate-critic labels its bullets the same way, and its Calibration
# paragraph carries a bullet list that belongs to it.
cfine=$(sec names "$PLUGIN_ROOT/agents/consolidate-critic.md" --fine)
printf '%s\n' "$cfine" | grep -qxF "what-to-argue-for-cutting/a-spike-note-doing-a-specs-job" \
    && ok "a consolidate-critic bullet is its own unit" || bad "the spike-note bullet has no fine name"
printf '%s\n' "$cfine" | grep -qxF "output/calibration" \
    && ok "a label paragraph is its own unit" || bad "Calibration has no fine name"
cal=$(sec split "$PLUGIN_ROOT/agents/consolidate-critic.md" --fine | grep -c '"name"')
[ "$cal" -eq 12 ] && ok "consolidate-critic holds 12 fine parts" || bad "expected 12 fine parts (got $cal)"

echo "== fine mode: drop one bullet =="
sec drop "$PLUGIN_ROOT/agents/plan-critic.md" --fine -s what-to-hunt/slug-collision -o "$W/nocollide.md"
if grep -q "Slug collision" "$W/nocollide.md"; then
    bad "the dropped bullet is still there"
else
    ok "drop takes the named bullet out"
fi
grep -q "Contract churn" "$W/nocollide.md" && grep -q "Missing baseline" "$W/nocollide.md" \
    && ok "its neighbours stay" || bad "drop of one bullet took a neighbour with it"
# The only difference is the bullet itself.
gone=$(diff "$PLUGIN_ROOT/agents/plan-critic.md" "$W/nocollide.md" | grep -c '^>')
[ "$gone" -eq 0 ] && ok "drop adds no line" || bad "drop added $gone line(s)"
sec drop "$PLUGIN_ROOT/agents/plan-critic.md" -s what-to-hunt/slug-collision >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "a unit name needs --fine" || bad "a unit name without --fine should exit 2 (got $rc)"

echo "== fixtures: frontmatter, preamble, a fence, a repeated heading =="
cat > "$W/a.md" <<'FIXTURE'
---
name: fixture
---

Text before the first heading.

# Title

Body of the title section.

```markdown
## Output
# Not a heading either
~~~
```

## Output

First output.

## Output

Second output.
FIXTURE

names=$(sec names "$W/a.md" | tr '\n' ' ')
want="_frontmatter _preamble title output output-2 "
[ "$names" = "$want" ] && ok "the names are '$want'" || bad "names should be '$want' (got '$names')"
roundtrip "$W/a.md" && ok "the fixture survives split and join" || bad "the fixture does not round trip"

# The fenced headings belong to the title section, so the count of sections
# proves that a fence is not a split point.
sec split "$W/a.md" -o "$W/a.json" >/dev/null
n=$(grep -c '"name"' "$W/a.json")
[ "$n" -eq 5 ] && ok "a heading inside a code fence starts no section" \
    || bad "the fixture should hold 5 sections (got $n)"

echo "== fine mode: the tail, a colon label, and a fence =="
cat > "$W/f.md" <<'FINE'
## Section

Intro at the section level.

- **First label.** Text of the first unit.
  - a nested bullet, which is continuation
- **Second label**: a colon label counts too.

A paragraph that returns to the level of the section.

Calibration. A label paragraph of its own.

- a plain bullet, which belongs to the paragraph

```markdown
- **Not a unit.** This bullet sits in a fence.
## Not a heading
```
FINE
fine_names=$(sec names "$W/f.md" --fine | tr '\n' ' ')
want="section section/first-label section/second-label section/_tail section/calibration "
[ "$fine_names" = "$want" ] && ok "the fine names are '$want'" \
    || bad "fine names should be '$want' (got '$fine_names')"
roundtrip "$W/f.md" --fine && ok "the fine fixture round trips" || bad "the fine fixture lost bytes"
[ "$(sec names "$W/f.md")" = "section" ] && ok "without --fine it stays one section" \
    || bad "the default split should give one section"

echo "== drop: the named section goes, and nothing else moves =="
cat > "$W/a_minus.md" <<'EXPECTED'
---
name: fixture
---

Text before the first heading.

# Title

Body of the title section.

```markdown
## Output
# Not a heading either
~~~
```

## Output

Second output.
EXPECTED
sec drop "$W/a.md" -s output -o "$W/dropped.md"
cmp -s "$W/a_minus.md" "$W/dropped.md" \
    && ok "drop of one section gives the expected bytes" \
    || { bad "drop of one section changed more than the section"; diff "$W/a_minus.md" "$W/dropped.md"; }

cp "$W/a.md" "$W/inplace.md"
sec drop "$W/inplace.md" -s _preamble -s output-2 -i
if grep -q "Second output" "$W/inplace.md" || grep -q "Text before" "$W/inplace.md"; then
    bad "--in-place should have dropped both named sections"
else
    ok "--in-place drops every named section"
fi

sec drop "$W/a.md" -s no-such-section >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown section name exits 2" || bad "an unknown name should exit 2 (got $rc)"

echo "== replace: one section takes new text =="
printf '## Output\n\nrewritten.\n\n' > "$W/new.md"
sec replace "$W/a.md" -s output --with "$W/new.md" -o "$W/replaced.md"
grep -q "rewritten." "$W/replaced.md" && ! grep -q "First output" "$W/replaced.md" \
    && grep -q "Second output" "$W/replaced.md" \
    && ok "replace swaps one section and leaves its neighbours" \
    || bad "replace should swap exactly one section"

echo "== fixtures: the line and file endings =="
printf '# A\n\ntext\n\n## B\n\nno trailing newline' > "$W/tail.md"
roundtrip "$W/tail.md" && ok "a missing trailing newline survives" || bad "a file with no trailing newline lost bytes"
[ "$(sec names "$W/tail.md" | wc -l)" -eq 2 ] && ok "that file splits in two" || bad "that file should split in two"

printf -- '---\r\nname: crlf\r\n---\r\n\r\n# One\r\n\r\ntext\r\n\r\n## Two\r\n\r\nmore\r\n' > "$W/crlf.md"
roundtrip "$W/crlf.md" && ok "a CRLF file survives" || bad "a CRLF file lost bytes"
crlf_names=$(sec names "$W/crlf.md" | tr '\n' ' ')
[ "$crlf_names" = "_frontmatter _preamble one two " ] \
    && ok "CRLF headings are found and named without the CR" \
    || bad "CRLF names should be '_frontmatter _preamble one two ' (got '$crlf_names')"

printf 'Only prose here.\nNo heading at all.\n' > "$W/flat.md"
roundtrip "$W/flat.md" && ok "a file with no heading survives" || bad "a file with no heading lost bytes"
[ "$(sec names "$W/flat.md")" = "_preamble" ] && ok "it is one _preamble section" \
    || bad "a file with no heading should be one _preamble section"

printf -- '---\nname: unclosed\ntext\n\n# Heading\n' > "$W/openfm.md"
roundtrip "$W/openfm.md" && ok "frontmatter with no closing fence survives" || bad "unclosed frontmatter lost bytes"
[ "$(sec names "$W/openfm.md" | head -1)" = "_preamble" ] \
    && ok "unclosed frontmatter is preamble, not frontmatter" \
    || bad "unclosed frontmatter should not be read as frontmatter"

echo "== the module API the search uses =="
out=$(PYTHONPATH="$PLUGIN_ROOT/evals/optimize" python3 - "$W/a.md" "$PLUGIN_ROOT" <<'PY'
import os
import sys

import sections

parts = sections.split_file(sys.argv[1])
candidate = sections.to_candidate(parts)
assert "_frontmatter" not in candidate, "frontmatter must stay out of a candidate"
assert "_preamble" not in candidate, "the preamble must stay out of a candidate"
assert candidate["output"].startswith("## Output"), "a component keeps its own heading"
candidate["output"] = "## Output\n\nrewritten.\n\n"
text = sections.join_sections(sections.from_candidate(parts, candidate))
assert "rewritten." in text and "First output." not in text, "the rewrite did not apply"
assert "Second output." in text, "the rewrite touched another section"
assert sections.join_sections(parts) == sections.read_file(sys.argv[1]), "join is not exact"

critic = os.path.join(sys.argv[2], "agents", "plan-critic.md")
fine = sections.split_file(critic, fine=True)
names = [s.name for s in fine]
assert "what-to-hunt/calibration" not in names, "Calibration sits under Output"
assert "output/calibration" in names, "fine=True must find the label paragraph"
assert len(sections.to_candidate(fine)) == len(names) - 2, "only the two meta parts stay out"
print("module ok")
PY
)
[ "$out" = "module ok" ] && ok "to_candidate and from_candidate carry one rewrite" \
    || bad "the module API failed: $out"

echo "== the script runs under uv as well as python3 =="
if command -v uv >/dev/null 2>&1; then
    uv_names=$(cd "$W" && uv run "$SCRIPT" names "$W/a.md" 2>"$W/uv.err")
    [ "$uv_names" = "$(sec names "$W/a.md")" ] \
        && ok "uv run gives the same names as python3" \
        || bad "uv run disagrees with python3 (stderr: $(cat "$W/uv.err"))"
else
    echo "  note uv is not installed here, so the uv check did not run"
fi

echo
echo "-------------------------------------"
printf 'PASS: %d   FAIL: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
