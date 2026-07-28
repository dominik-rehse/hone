# Change under review (consolidate step)

## Plan (in hand, to be deleted): search/switch-to-trigram
Replace the LIKE-based product search with trigram similarity.

## Diff summary
- src/search/query.ts: search now uses a pg_trgm similarity query with a 0.3
  threshold instead of `LIKE '%term%'`.
- src/search/query.test.ts: typo-tolerant match ("sheos" finds "shoes"),
  ranking by similarity, and the old exact-substring case still passing.

## What this change left behind (durable layer)
- New Decision docs/decisions/search-backend.md, full text:

  > # Search backend
  > Product search runs on Postgres pg_trgm similarity, not an external search
  > service. Chosen because the catalogue (40k rows) fits comfortably in
  > Postgres and one less stateful service keeps the ops surface flat for a
  > two-person team.
  > Rejected: Elasticsearch — better relevance tooling, but a second stateful
  > service to run, snapshot, and upgrade. Revisit if the catalogue passes ~1M
  > rows or we need faceting.

- docs/notes/search.md unchanged.

## Types / abstractions touched
- none new.
