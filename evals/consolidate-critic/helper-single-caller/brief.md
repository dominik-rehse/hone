# Change under review: `listing/page-param`

## Diff (consolidate step)

```diff
+++ b/src/listing/page.ts
@@
+/** The page a request asks for, held inside 1..lastPage. */
+export function requestedPage(query: URLSearchParams, lastPage: number): number {
+  const raw = Number.parseInt(query.get("page") ?? "1", 10)
+  return clampPage(Number.isNaN(raw) ? 1 : raw, lastPage)
+}
+
+function clampPage(page: number, lastPage: number): number {
+  return Math.min(Math.max(page, 1), Math.max(lastPage, 1))
+}
```

```diff
+++ b/src/listing/page.test.ts
@@
+test("reads the page from the query", ...)
+test("answers page 1 for a missing or non-numeric page", ...)
+test("holds a page past the end at the last page", ...)
+test("answers page 1 for an empty listing", ...)
```

```diff
+++ b/src/listing/route.ts
@@
-  const page = Number(req.query.get("page"))
+  const page = requestedPage(req.query, lastPage)
```

# Context

The Plan for this change is `listing/page-param`. Consolidate deleted it.

Decisions touched: none. Notes touched: none. `docs/notes/listing.md` exists
and this change did not alter it. `clampPage` has no other caller in the
repository.
