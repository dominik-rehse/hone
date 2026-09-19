Review the change below.

## Plan: calendar/shared-room-merge

### What
Add `src/merge.js` with `mergeCalendars(a, b)`. It takes the two day calendars
two teams keep for one room and gives back a third that holds the bookings of
both. A booking both teams entered counts once. Where two bookings want minutes
the room cannot give twice, the one from the first calendar keeps the room. The
other goes on a `dropped` list. The merged day opens as early and closes as
late as either team needs, and the merge leaves both calendars alone. Add
`formatMerged`
to `src/format.js`, so the display can show the day with the bookings the merge
could not keep underneath it.

### Why
Aurora belongs to two teams since the move, and each keeps its own day in the
booking tool. Facilities reconciles the two by hand every morning and mails the
losing team. Twice last month a team walked into a room another team was
already sitting in.

### How I'll know it works
The morning team's three bookings and the afternoon team's three come back as
five, because the all-hands both entered counts once. A booking that clashes
with one the first calendar holds does not come back, and is on the dropped
list instead. Both calendars still read as they did. Two calendars for
different rooms are refused. The display shows a merged day with its dropped
bookings under it, and a merge that kept everything reads like a plain day.

### Notes for the loop
- Adds `src/merge.js` and `tests/merge.test.js`. Touches `src/format.js` and
  `tests/unit/format.test.js`.
- Not a critical path. Facilities runs the merge and reads the result.
