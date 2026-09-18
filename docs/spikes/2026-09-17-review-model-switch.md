# Spike: does the reviewer's model change what the nested review catches?

**Date:** 2026-09-17 · **Status:** frozen. Written once, never maintained
against the code.

## Question

The roadmap says that nothing measures the floor of the nested
`/code-review`. One data point existed: claude-sonnet-5 landed
`parallel-paths` in silence, and the review on claude-opus-5 at `high` did
not find the second path either. Can the lab count a catch rate per review
model?

## What I did

Added `--review-model` to `evals/lab/run.sh`, and the check helper
`review_named`. The helper notes two things per run. The first is whether
the review's own output names the seeded defect. The second is whether the
run's brief to the review named it already. Wrote the scenario `defect-in-hunk`, whose defect
sits in the function that the Plan edits. Then ran ten runs on claude
2.1.274 with the full plugin, under `/var/tmp`:

- `defect-in-hunk`: claude-sonnet-5 builds, and the review runs once each
  on claude-opus-5, claude-sonnet-5, and claude-haiku-4-5. One more run has
  claude-opus-5 for both.
- `parallel-paths`: claude-sonnet-5 builds, and the review runs twice each
  on the same three models.

## Finding

The builder decides first whether the review is tested at all. A brief that
names the defect hands the review its finding. So only the runs with a
silent brief count toward a catch rate.

`defect-in-hunk` does not separate the reviewers. Sonnet as the builder
never saw the defect: its brief was silent in three runs of three. Each
review named it, the one on haiku too. Haiku wrote that the line "was
unchanged by the diff but is in the touched function, placing it in review
scope per the recipe". All three runs then declined the finding as not part
of the Plan, and each recorded it in the commit body. So all three passed
with the defect still in the code. Opus as the builder found the defect during
build. It fixed it in a red-green cycle and a commit of its own, before
the review ran.

`parallel-paths` separates them a little:

| review model | runs | silent brief | caught on a silent brief |
|---|---|---|---|
| claude-opus-5 | 2 | 0 | none to count |
| claude-sonnet-5 | 2 | 2 | 2 |
| claude-haiku-4-5 | 2 | 1 | 0 |

The one miss is the one fail of the ten runs. Sonnet landed the checkout
fix, and the review on haiku said nothing about the sandbox path. Nothing
durable names it. In three of the six runs sonnet found the sandbox path by
itself, so the review had nothing left to catch.

These counts are far too small to move the pin. They show two things. The
switch works, and the count needs the second note, because half of the
`parallel-paths` runs did not test the review. And every tier catches a defect inside the touched
function. So a scenario that prices a reviewer has to hide its defect
outside the diff, as `parallel-paths` does.

One more reading concerns the value of the review step itself. In all three
sonnet runs of `defect-in-hunk` the review was the only thing that saw the
defect. Without the review step those three runs would have landed it in
silence.

## Where it landed

`evals/lab/README.md` *The review's catch rate* has the method.
`docs/roadmap.md` *Model assignment and recalibration* points at the
switch. The pin of the review stays on claude-opus-5.
