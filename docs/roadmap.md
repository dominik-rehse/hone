# Roadmap: what is open

This page lists what is open in the work on hone itself, and what the
maintainer decided. [*Goals*](model.md#goals) has the outcomes.
[`development.md`](development.md) has the procedure that judges a change,
and [`releasing.md`](../.claude/rules/releasing.md) has the release gates.
The history is in the dated notes under `docs/spikes/` and in git.

## Open

- *Outcomes with no mechanism of their own.* Three are known.
  - A `Governs:` line ties a document to a path. Nothing ties a sentence
    to the value that it repeats, so a change can make a sentence false
    and never open its document.
  - Nothing turns a fact that prose holds into a type.
  - Nothing chooses among the valid endings of a run. A candidate is an
    order of preference in the run skill.

  The seeded scenarios measure the first two, and the baseline of
  2026-09-18 held both in three runs of three.
- *The lab's noise floor.* Three identical passes outside the repository
  are still owed, about 100 dollars. Four passes on 2026-09-18, on four
  versions of the plugin, gave 52 passes of 52.
- *The ten-vote rule.* It differs from the maintainer's earlier rule that a
  cut needs an unmoved tally. The maintainer has not confirmed it.
- *The garden gate.* Its release gate runs on opus, and the measured floor
  is sonnet. `evals/floors` names sonnet.
- *A cut of a critic section.* The section ablation of 2026-09-17 ran on
  sonnet, and the critics run on opus since 0.54.0. It needs the campaign
  again on opus first, about 10 dollars per critic.
- *Coverage.* No suite measures `skills/plan/` or `skills/setup/`, so the
  procedure cannot judge a change there. A bounce of the `plan-critic` has
  no lab measure. `casual-fix` counts the reach by hand, and a measure
  `reached` would let the procedure count it.
- *The mock on `PATH`.* One haiku run walked around a commit hook with a
  mock of a missing tool. No guard reads that route. Whether it is inside
  hone's threat model is open.
- *A reviewer from another model family.* Author and reviewer may share
  blind spots. `--review-model` and a defect outside the diff can price
  the idea. A second vendor CLI is a heavy dependency for a small plugin.
- *Automated search over candidates.* A candidate that needs the lab costs
  10 to 50 dollars to judge. So only a search at the unit level is
  affordable, and the unit level pins little.
- *hone on hone.* This repository is not self-hosted, and
  [`development.md`](development.md) *Change briefs* says so. Running
  hone's own loop here is a project of its own.

## Decided

- *The `consolidate-critic` stays* (2026-09-18). No case shows that its cut
  bullets change a verdict, and no run shows that they change a codebase.
  The maintainer decided not to test its removal, which would cost about
  60 dollars.
- *A deterministic check needs no measured gain* (2026-09-18). It is rule 5
  of the procedure.
