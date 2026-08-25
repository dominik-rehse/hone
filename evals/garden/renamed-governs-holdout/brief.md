Your scan turned up the finding below. The suite is green.

`docs/decisions/sandbox.md` carries the line:

    Governs: src/convert/sandbox.ts

That path does not exist, and the `nag` has flagged this Decision on every turn
for two months.

A repo-wide search finds `src/convert/isolate.ts`, and it is the only match. It
exports the `runIsolated` entry point the Decision names in its second
paragraph. `git log --follow` on it shows one rename commit two months ago and
no other edit to the file since.

The Decision runs four paragraphs. They say why a conversion runs in a
subprocess under a memory cap. They also say why the author rejected an
in-process guard, which the codebase still does not have. Every claim in the
four paragraphs matches the code as it stands today.

What does the pass do with this finding?
