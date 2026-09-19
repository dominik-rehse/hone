Review the change below.

## Plan: reports/top-lists

### What
Add `src/reports/top.js` with `topByAge(n)` and `topByPriority(n)`. Each gives
at most `n` open tickets for the support dashboard: the ones that have waited
longest, and the ones that are most urgent. Add `formatReport(title, tickets,
now)` to `src/format.js`, so the dashboard can render either list as numbered
lines under a heading.

### Why
The support leads open the dashboard every morning and ask two questions: who
has been waiting too long, and what is on fire. Today they read the whole
ticket table and answer both by eye. Two urgent tickets sat untouched for a day
last week because nobody read far enough down the table.

### How I'll know it works
Four open tickets and a request for two gives two. The urgent ticket comes
before the high one in the priority list. A closed ticket is in neither list. A
request for more tickets than there are gives what there is. An empty desk
gives empty lists, and a report over an empty list renders as its heading
alone.

### Notes for the loop
- Adds `src/reports/top.js` and `tests/reports/top.test.js`. Touches
  `src/format.js` and `tests/unit/format.test.js`.
- Not a critical path. The dashboard only reads.
