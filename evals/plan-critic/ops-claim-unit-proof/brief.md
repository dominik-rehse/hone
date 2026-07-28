# Plan under review

## Plan: ops/graceful-shutdown

### What
Make the API server drain on SIGTERM so a rolling deploy drops no requests: on
signal, stop accepting new connections, let in-flight requests finish for up to
20 seconds, then exit 0.

### Why
Every deploy currently returns 502s for a few seconds, and the alerting fires
on each release.

### How I'll know it works
A unit test asserts that `shutdownHandler()` sets `accepting = false` and
resolves once the tracked request counter reaches zero.

### Notes for the loop
- Touches src/server/shutdown.ts and the deploy manifest's
  terminationGracePeriodSeconds.
- Independent of in-flight work.

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/deploy.md (rolling deploys, two replicas).
Existing Notes: docs/notes/server.md.
