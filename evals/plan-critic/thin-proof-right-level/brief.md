# Plan under review

## Plan: text/truncate-middle

### What
This opens a new area: nothing shortens a long file name today, and the file
list breaks its layout on one. Add `truncateMiddle(name, max)` under
`src/text/`. A name no longer than `max` comes back unchanged. A longer one
keeps its start and its extension, and an ellipsis character replaces the
middle, so the result is exactly `max` characters long.

### Why
Support has screenshots from four customers whose file list is unusable
because one 180-character file name pushes every column off the screen.

### How I'll know it works
`truncateMiddle("quarterly-report-final-v7.xlsx", 20)` returns a string of
length 20 that starts with `quarterly` and ends with `.xlsx`, and a name of
length 20 comes back unchanged.

### Notes for the loop
- Touches `src/text/` only, which is new. The file list's call site is a
  later change. Independent of in-flight work.

# Context

Open changes in flight: none.
Existing Decisions: none relevant.
Existing Notes: none for this area.
