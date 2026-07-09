# Plan under review

## Plan: auth/session-timeout

### What
Add an idle-session timeout so sessions expire after inactivity.

### Why
Security: an unattended logged-in session is a risk.

### How I'll know it works
TBD — figure out during implementation. It should work correctly and handle
errors.

### Notes for the loop
- Timeout duration: TBD (maybe 15 or 30 minutes?).

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/auth-strategy.md.
Existing Notes: docs/notes/auth.md.
