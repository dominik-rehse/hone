# Spike: where do the land gates get rubber-stamped in real use?

**Date:** 2026-08-12, re-audited 2026-08-30 · **Status:** frozen. Written
once, never maintained against the code.

## Question

Across the four repositories that use hone day to day, which gate records
carry real evidence? And which ones did a human or the loop stamp without
reading? The roadmap's work on evaluating hone needed the answer before any
gate prose got trimmed.

## What I did

Read every merge commit body and every surviving grant and sign-off file in
the four consumer repositories (`agent`, `capital-provider-db`, `fileduct`,
`mailduct`). Counted how often each gate fired, and read the text each
record carried. Repeated the reading on 2026-08-30, after the fixes the
first pass produced had shipped.

## Finding

First pass, 262 hone merges. The authority gate fired about five times, and
every grant carried genuine review text. The proof gate was where the
stamping happened. Three of ten sign-off files in `agent` held the unedited
placeholder "what you ran and the outcome". Two of those three were changes
that added their own probe, where the bootstrap rule forced a sign-off with
nothing to run. All four repositories had grown substantive `proof.sh`
adapters. In `capital-provider-db`, the decision doc on land gates
contradicted the actual irreversible-paths policy and still named a marker
retired in 0.19. Three causes. The exit-7 message named no concrete check.
Consolidate had deleted the Plan, and with it the "how I will know it works"
section. And `attest` validated only the commit hash, never the text.

Second pass, after 0.25.0. The sign-off placeholders were gone, and the
consumer repositories had fixed the open items. The stamping had moved to the grant text, which no
helper validated. The only human-typed grant in `capital-provider-db` was
the literal placeholder "rehse/why", on a database redesign. `agent` had
grants reading "to continue" and "approved". `fileduct` landed a 272-line
deploy diff on a grant reused after 23 days. Every sign-off text written
before 0.47.0 had evaporated. The files were gitignored, and nothing copied
them into the merge body. Humans bypassed the loop directly on main
for docs, policy, and secrets in all four repositories. One more mechanical
finding: the bash-guard's formatter rule fired on the model's habitual bare
`bunx dprint fmt` chained with the plan commit. The ask reached only the
operator, never the model.

## Where it landed

0.25.0 (2026-08-12): the proof trailer carries the check and exit 7 prints
it. `attest` refuses a placeholder, and exit 8 prints a diffstat. A change
to the adapter itself gets an explicit hand-run instruction. 0.47.0: a green
land consumes the grant, so a stale one cannot open the gate for a later
change. 0.48.0 (2026-08-30): `grant` refuses an empty or placeholder text,
exact or half-edited, and the plan skill spells the scoped formatter run.
0.52.0 (2026-09-17): the sign-off became the human's act, and the loop hands
over the check's output instead. The reasoning lives in
[`../model.md`](../model.md) under *The proof boundary*, and the mechanics
in [`../reference.md`](../reference.md) under *Land gates*. The consumer
repositories fixed their own leftovers the same day: a parked browser in
`agent`, an adapter timeout, and dev-server smokes classed as proof.
