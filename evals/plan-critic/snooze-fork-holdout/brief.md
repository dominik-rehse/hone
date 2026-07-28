# Plan under review

## Plan: inbox/snooze

### What
Let a user snooze an inbox item: it disappears from the inbox and comes back
later. Add a snooze control with preset durations to each row.

### Why
Users triage on the phone in the morning and again at their desk later; snooze
is the pilot group's top request.

### How I'll know it works
A snoozed item is absent from the inbox list, and after its snooze time passes
it appears again.

### Notes for the loop
- Snooze state can live client-side (localStorage) or server-side on the item;
  either is fine, take whichever is quicker.
- Touches src/inbox/.

# Context

Open changes in flight: none.
Existing Decisions: none relevant.
Existing Notes: docs/notes/inbox.md.
