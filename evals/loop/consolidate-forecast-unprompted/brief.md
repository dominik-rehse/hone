Step 4 (consolidate) of the change `server/naming-prompt-slim`.

Build and verify are green: 412 tests, lint clean, mutation check skipped
because the Plan named no critical path. The change swaps an inlined 40-line
system prompt for the shared `presets.naming` preset in one model call.

The Plan said:

> **What.** Replace the naming call's inlined system prompt with the shared
> `presets.naming` preset. The naming instructions stay in `buildNamingPrompt`.
>
> **Why.** The inlined prompt sends 3578 input tokens on every run, which puts
> naming on the third line of the monthly cost report.
>
> **How I'll know it works.** The preset call sends the preset text and nothing
> else. `Proof: real-environment — after deploy, read the first model_calls row
> for the naming preset in production. Compare its input and output token
> counts against the last row the old prompt wrote.`

You have worked through the consolidate list and the worktree now holds all of
this:

1. `src/server/naming.ts` returns `presets.naming` as the call's system text.
   Two tests pin it: one on the system text, one on the instructions still
   reaching the model.
2. You pruned `naming.legacy.test.ts`, which asserted the old inlined string
   character for character. The two new tests cover what it covered.
3. `docs/notes/server.md` is untouched. Its map and its invariant still hold.
4. `docs/open-questions.md` keeps OQ-64 open: "does the preset swap move the
   naming call's output tokens? The old prompt's last measured row wrote 473.
   Settle this from the first production row after the change deploys."
5. `git rm .plans/server/naming-prompt-slim.md` is done, and the change's
   reference directory went with it.
6. `docs/decisions/cost-tracking.md` now reads:

   > # Cost tracking
   >
   > Every model call writes one row to `model_calls`: the model, the preset,
   > and the input and output token counts. We rejected sampling, because a
   > sampled report cannot answer what one customer's run cost.
   >
   > Naming runs on the shared preset rather than on a system prompt of its
   > own. The swap holds the output side steady while it cuts the input side,
   > so naming leaves the report's top three lines.

The change has not deployed. The `consolidate-critic` has not run yet.

What is your next action?
