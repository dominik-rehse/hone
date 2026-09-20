# Plan under review

## Plan: search/strip-metadata-block

### What
`buildChunks` in `src/search/indexer.ts` chunks a recipe file whole today, its
leading metadata block included. Strip that block before chunking. Bump
`INDEX_VERSION` in `src/search/store.ts` from 4 to 5, so the derived chunk
store wipes and rebuilds every recipe on the next start.

### Why
A search for a dish returns a snippet that begins `servings: 4`, not the first
line of the method. Three people on the kitchen team reported it this month.

### How I'll know it works
A unit test feeds `src/search/__fixtures__/with-block.md` to `buildChunks` and
asserts that no chunk holds a `---` line or a `servings:` line. A second test
feeds a file without a block and asserts the chunks are unchanged. A third
asserts that `INDEX_VERSION` 5 makes `openStore` rebuild rather than read the
stored rows.

### References
- src/search/__fixtures__/with-block.md — one recipe file with the block.

### Notes for the loop
- Touches `src/search/` only. Independent of in-flight work.

# Context

Open changes in flight: none.

Existing Decisions: none relevant.

Existing Notes: `docs/notes/search.md`, which this change does not alter:

```markdown
# search

The index covers every recipe in the archive, from all three importers.

- `src/search/indexer.ts` walks the archive and chunks each file.
- `src/search/store.ts` holds the derived chunk rows. A bump of
  `INDEX_VERSION` wipes and rebuilds all of them in one pass.
- `src/search/query.ts` ranks chunks and returns the first line of the best
  chunk as the snippet.

The three importers write different shapes.

- The web importer writes a `# <dish>` heading, then the method.
- The card importer writes a `# <dish>` heading, then the method.
- The scan importer writes neither a heading nor a prose title. For a scanned
  card the metadata block is the only place that holds the dish name, the
  source cookbook, and the year.

Invariant: every chunk row carries the id of the file it came from.
```
