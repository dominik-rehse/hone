# Plan under review

## Plan: export/csv-escaping/quotes

### What
Handle embedded double quotes in CSV fields: wrap the field in double quotes
and double each inner quote, per RFC 4180.

### Why
Follow-up to the comma work: embedded quotes are the other corruption customers
reported.

### How I'll know it works
A test: a field containing `say "hi"` round-trips through a standard CSV parser
unchanged.

### Notes for the loop
- Small and self-contained.

# Context

Open changes in flight:
- .plans/export/csv-escaping.md, "Escape commas and newlines in CSV fields, in
  src/export/csv.ts." In a worktree, not yet landed.

Existing Decisions: docs/decisions/export-format.md.
Existing Notes: docs/notes/export.md.
