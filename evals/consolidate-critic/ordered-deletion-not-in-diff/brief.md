# Change under review: `report/generated-fixtures`

## Diff (consolidate step)

```diff
+++ b/src/report/fixtures.ts
@@
+/** Load a fixture by name from the current fixture set. */
+export function loadRows(name: string): Row[] {
+  return JSON.parse(readFileSync(join(CURRENT, name), "utf8")).rows
+}
```

```diff
+++ b/src/report/render.ts
@@
-  const rows = JSON.parse(readFileSync(legacyPath(name), "utf8"))
+  const rows = loadRows(name)
```

```diff
+++ b/src/report/__fixtures__/current/monthly.json
@@
+{ "rows": [ ... ] }
```

```diff
+++ b/src/report/render.test.ts
@@
-  const rows = load("__fixtures__/legacy/monthly.json")
+  const rows = loadRows("monthly.json")
```

# Context

The Plan for this change is `report/generated-fixtures`. Consolidate deleted
it. Its *What* ended with this sentence:

> Delete `src/report/__fixtures__/legacy/` once the tests read the new
> fixtures. Nothing else in the repository names that directory.

Decisions touched: none. Notes touched: none. `docs/notes/report.md` exists
and this change did not alter it.

The working tree under `src/report/` now holds:

```
fixtures.ts
render.ts
render.test.ts
__fixtures__/current/monthly.json
__fixtures__/legacy/monthly.json
__fixtures__/legacy/quarterly.json
```

A repository-wide search for `legacy` finds it in no other file.
