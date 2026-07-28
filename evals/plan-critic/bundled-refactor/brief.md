# Plan under review

## Plan: search/filters

### What
Add category and price-range filters to product search, in src/search/. While
in there, also rename the `Repo` classes to `Store` across src/ (about thirty
files), since the old name keeps confusing new contributors.

### Why
Filters: the storefront team's top request. Rename: long-standing naming debt,
and touching search anyway makes it a convenient moment.

### How I'll know it works
Filter tests: a category filter narrows results to that category; min/max
price bounds are respected; combined filters intersect. The rename is proven by
the suite staying green.

### Notes for the loop
- The filter work is confined to src/search/; the rename touches most of src/.

# Context

Open changes in flight: none.
Existing Decisions: none relevant.
Existing Notes: docs/notes/search.md.
