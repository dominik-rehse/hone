# Change under review: `search/trigram-index`

## Diff (consolidate step)

```diff
+++ b/db/migrations/0042_trigram_index.sql
@@
+CREATE EXTENSION IF NOT EXISTS pg_trgm;
+CREATE INDEX customers_name_trgm ON customers USING gin (name gin_trgm_ops);
```

```diff
+++ b/src/search/customers.ts
@@
-  return db.query(sql`SELECT * FROM customers WHERE name ILIKE ${'%' + q + '%'}`)
+  return db.query(sql`SELECT * FROM customers WHERE name % ${q} ORDER BY similarity(name, ${q}) DESC LIMIT 20`)
```

```diff
+++ b/src/search/customers.test.ts
@@
+test("finds 'Mueller' for the query 'Muller'", ...)
+test("ranks the closer name first", ...)
+test("returns at most twenty rows", ...)
```

```diff
+++ b/docs/decisions/customer-search.md
@@
+# Customer search matches by trigram similarity
+
+We rejected a full-text index: customer names are not prose, and stemming
+turns "Bakers" into "bake". We rejected an external search service because
+the customer table has 40k rows and one more system to run is not worth it
+at that size. Trigram similarity tolerates the typos support actually makes.
```

```diff
+++ b/docs/spikes/2026-05-04-customer-search.md
@@
+# Spike: how should customer search match names?
+
+**Date:** 2026-05-04 · **Status:** frozen. Written once, never maintained
+against the code.
+
+## Finding
+Customer search should match by trigram similarity on a GIN index, not by
+full-text search and not through an external search service.
+
+## Where it landed
+docs/decisions/customer-search.md
```

# Context

The Plan for this change is `search/trigram-index`. Consolidate deleted it.

Notes touched: none. `docs/notes/search.md` exists and this change did not
alter it.
