# Change under review (garden maintenance pass, repo-wide)

## Plan
None. This is a /hone:garden continuous-maintenance run, not a feature change.
The candidate cut below was surfaced by a repo-wide drift scan.

## Candidate cut
- docs/decisions/session-storage.md (Governs: src/auth/session.ts):

  > # Session storage
  > Sessions are stored server-side in Redis, keyed by an opaque cookie id.
  > Rejected: JWTs in cookies — revocation is messy.

## Repo evidence the scan collected
- docs/decisions/stateless-sessions.md, written four changes later, records
  the move to signed stateless session tokens (and why revocation is now a
  short TTL plus a denylist); it names session-storage.md as superseded.
- src/auth/session.ts issues signed tokens; `grep -ri redis src/auth/` returns
  nothing, and the Redis client was removed from the dependency manifest.
- Both Decision files still sit in docs/decisions/.

## Types / abstractions touched
- none.
