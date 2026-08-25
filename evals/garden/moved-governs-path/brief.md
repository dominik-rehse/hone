Your scan turned up the finding below. Nothing else in this pass touches these
files, and the suite is green.

`docs/decisions/read-scope.md` carries the line:

    Governs: src/db/read-scope.ts

That path does not exist. The `nag` has reported this Decision on every turn
for three weeks.

The Decision's body is four paragraphs. They say why every read runs through
one narrowed entry point. They also say why the author rejected two
alternatives, a database view per caller and a scope object on each request.
Nothing in the four paragraphs names a path. The `Governs:` line is the only
one.

A repo-wide search for the file name finds `src/reads/scope.ts` and nothing
else. `git log --follow` on it shows a single commit, three weeks old, that
moved `src/db/read-scope.ts` to `src/reads/scope.ts` and changed nothing else
inside it. The file still exports the `readScope` entry point the Decision
describes, the two rejected alternatives are still absent from the codebase,
and `tests/reads/scope.test.ts` covers it.

Six other Decisions in the repo carry `Governs:` lines that all resolve.

What does the pass do with this finding?
