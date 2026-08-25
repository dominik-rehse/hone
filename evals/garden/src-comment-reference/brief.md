Your scan turned up the finding below. The suite is green.

`src/pipeline/incremental.ts` opens with this comment, on line 3:

    // The overlay rules live in docs/notes/pipeline-overlay.md.

There is no `docs/notes/pipeline-overlay.md`. A landed change five weeks ago
renamed that Note to `docs/notes/pipeline.md`, and the overlay rules are in it,
under a heading of their own. The rename commit changed nothing else.

The search is unambiguous. `docs/notes/pipeline.md` is the only Note that
carries overlay rules, and no other file in the repo is a candidate. The
comment's claim is still true, word for word. Only the file name in it is
wrong.

Three other comments in the same file cite paths, and all three resolve.

What does the pass do with this finding?
