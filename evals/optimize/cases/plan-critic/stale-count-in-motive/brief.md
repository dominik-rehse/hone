# Plan under review

## Plan: docs/heading-ids

### What
The renderer derives a heading's anchor id from the heading text today, so
rewording a heading moves its anchor. Write an explicit `{#id}` marker on each
heading of `docs/manual.md` that carries none, and make the renderer prefer
the marker over the derived id. A heading that already carries a marker keeps
the one it has. Each new marker repeats, character for character, the id the
renderer derives from that heading today. So no anchor moves.

### Why
Twelve of the manual's headings carry no marker, so twelve anchors move
whenever somebody rewords a heading. Two links in the onboarding page broke
that way last month.

### How I'll know it works
The renderer writes, for each row of `.plans/docs/heading-ids/ids.tsv`, the id
that row names. A test asserts that the rendered page carries exactly those
marker ids, and that each link in
`.plans/docs/heading-ids/links.txt` still resolves. Another test rewords one
heading in the fixture and asserts the id stays.

### References
- .plans/docs/heading-ids/ids.tsv — the eleven headings that carry no marker
  today. Each row holds the heading text and the exact id to write for it.
- .plans/docs/heading-ids/links.txt — every link into the manual, from inside
  the repository and from the two published pages that point at it.

### Notes for the loop
- Touches `src/render/` and `docs/manual.md` only. Independent of in-flight
  work.

# Context

Open changes in flight: none.

Existing Decisions: `docs/decisions/anchor-stability.md`. A published link into
the manual must keep resolving, so an anchor never moves once somebody has
linked to it.

Existing Notes: `docs/notes/render.md`.
