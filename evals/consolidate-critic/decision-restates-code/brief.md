# Change under review (consolidate step)

## Plan (in hand, to be deleted): api/pagination
Add cursor-based pagination to the list endpoint.

## Diff summary
- src/api/list.ts: `list(cursor?, limit=50)` returns `{ items, nextCursor }`.
- src/api/list.test.ts: tests for first page, next page, last page (nextCursor
  null), and limit clamping to 100.

## Durable residue produced by this change
- New Decision docs/decisions/pagination.md, full text:

  > # Pagination
  > The `list` function takes an optional `cursor` and a `limit` that defaults to
  > 50 and is clamped to 100. It returns an object with `items` and `nextCursor`.
  > When there are no more results, `nextCursor` is null. The cursor is the id of
  > the last item on the page.

- docs/notes/api.md unchanged.

## Types / abstractions touched
- Return type `Page<T> = { items: T[]; nextCursor: string | null }`. Two callers.
