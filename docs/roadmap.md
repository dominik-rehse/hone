# Roadmap: what is open

This page lists what is open in the work on hone itself, and what the
maintainer decided. [*Goals*](model.md#goals) has the outcomes.
[`development.md`](development.md) has the procedure that judges a change,
and [`releasing.md`](../.claude/rules/releasing.md) has the release gates.
The history is in the dated notes under `docs/spikes/` and in git.

## Open

- *Outcomes with no mechanism of their own.* Three are known. The lab
  measures each one, and opus holds the first two today. So no mechanism
  can show a gain there yet, and the procedure rejects prose that grows
  with none.
  - A `Governs:` line ties a document to a path. Nothing ties a sentence
    to the value that it repeats. `untied-sentence` seeds two such
    sentences, and three runs of three left none false.
  - Nothing turns a fact that prose holds into a type. `seeded-structure`
    held it in three runs of three.
  - Nothing chooses among the valid endings of a run. In seven passes of
    2026-09-18, two scenarios changed between a land and another valid
    ending, once each. Most other splits are whether a change earns a
    Decision ([`endings-on-opus`](spikes/2026-09-18-endings-on-opus.md),
    [`lab-noise-floor`](spikes/2026-09-18-lab-noise-floor.md)).

  A harder seed, or a run below the floor, is what can show a deficit.
- *Two real fails in the noise floor.* Three identical passes gave 46
  passes of 48 ([`lab-noise-floor`](spikes/2026-09-18-lab-noise-floor.md)).
  Each fail is a candidate for the run skill, with a measure that exists.
  - One run read the permission denials in the review's envelope as a
    degraded review, and it paid for a second review. The denials are the
    design, and 25 of 26 envelopes carry one. The measure is `reviews`.
  - One stop report offered two actions and recommended neither. The
    measure is `stop_actionable`.

  The release gate demands a pass with no fail, and two of the three
  passes had one. Whether the gate keeps that demand is open.
- *The ten-vote rule.* It differs from the maintainer's earlier rule that a
  cut needs an unmoved tally. The maintainer has not confirmed it.
- *A cut of a critic section.* Both campaigns found none
  ([`section-ablation-on-opus`](spikes/2026-09-18-section-ablation-on-opus.md)).
  A cut needs a case that aims at the section, and thirteen sections of
  the two critics have none. `thin-proof-right-level` moves with any
  shorter prompt, so its brief needs a firmer proof first.
- *Coverage.* The plan skill and the setup skill have one scenario each,
  with one sketch and one misfit. A sketch with a fork, where the right
  answer is a bounce, has no scenario.
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
