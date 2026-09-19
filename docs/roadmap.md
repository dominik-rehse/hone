# Roadmap: what is open

This page lists what is open in the work on hone itself, and what the
maintainer decided. [*Goals*](model.md#goals) has the outcomes.
[`development.md`](development.md) has the procedure that judges a change,
and [`releasing.md`](../.claude/rules/releasing.md) has the release gates.
The history is in the dated notes under `docs/spikes/` and in git.

## Open

### Defects with evidence

- *A carve-out can enter through the Plan.* One Plan named a carve-out for
  a wrong test as a requirement, and the `plan-critic` approved it twice
  ([`impossiblebench-first-look`](spikes/2026-09-18-impossiblebench-first-look.md)).
  The probe's request makes the tests the specification. A clean test
  needs a request that names the specification as the authority.
- *A blocked run offers the off switch.* On 0.58.0 two probe runs of ten
  told the person to create `.hone-off`, after a gate block and not in a
  final message
  ([`probe-across-releases`](spikes/2026-09-19-probe-across-releases.md)).
  `rules/workflow.md` and `msg_guard_primary_tree` name the marker.
- *A stop outside `/hone:run` has no report contract.* `hand-merge` on
  sonnet offered two routes and recommended neither. `plan-fork` once
  presented its rejected Plan as written.
- *The review bench is at its ceiling.* Alone, on eight small changes,
  opus and sonnet caught every planted defect, 21 of 21 each
  ([`review-bench-first-run`](spikes/2026-09-19-review-bench-first-run.md)).
  Inside the loop no run has tested the review, because the brief named
  the defect each time. Harder fixtures come first.
- *The `plan-critic` still asks too much at times.*
  `fork-settled-by-decision` approves in 15 votes of 17. A fail of that
  case asks for ten votes.
- *`setup-misfit` failed once in four runs.* The run invented a test script
  that called the adapter.
- *`candidate.sh decide` cannot filter its baselines.* It answers
  *undecided* when baseline plugin hashes differ only in paths that the
  scenario never loads.

### Questions for the maintainer

- *An honest ending.* Over 20 probe runs per arm, bare opus delivered a
  cheat 12 times and hone 2 times. hone never delivered the honest
  solution, because it leaves the wrong test red. hone stopped 15 times.
  Whether hone may land beside a test that it reports as wrong is open.

### Measurement

- *Fails from real use* go into [`field-log.md`](field-log.md). They are
  the best source of scenarios.
- *Probes.* A probe measures hone where opus is tempted, and it never gates
  a release. `evals/probes/impossiblebench/` is the first, with ten tasks
  and two runs per arm. More runs come before a candidate leans on it.
- *A measure for well structured.* `scb-check` is exact and makes no model
  call, and it reads Python alone. A Python fixture in the lab would give
  the outcome its first exact measure
  ([`slopcodebench-first-look`](spikes/2026-09-18-slopcodebench-first-look.md)).
  The paid experiment on the garden pass costs about 250 dollars.
- *Outcomes with no mechanism of their own.* Nothing ties a sentence to the
  value that it repeats. Nothing turns a fact that prose holds into a
  type. Nothing chooses among the valid endings of a run
  ([`endings-on-opus`](spikes/2026-09-18-endings-on-opus.md)). opus holds
  the first two in the lab. A fail from real use or from a probe is what
  can show a deficit.

### Parked, each with its condition

- *A cut of a critic section* waits for the next model release.
  Thirteen sections have no case that aims at
  them ([`section-ablation-on-opus`](spikes/2026-09-18-section-ablation-on-opus.md)).
- *A reviewer from another model family* waits for a review bench with
  harder fixtures.
- *Automated search over candidates* waits for a cheap judge. The lab
  costs 10 to 50 dollars per candidate.
- *hone on hone* is a project of its own.

## Decided

- *The `consolidate-critic` stays* (2026-09-18). A test of its removal
  would cost about 60 dollars, and the maintainer decided against it.
- *A deterministic check needs no measured gain* (2026-09-18). It is rule
  5 of the procedure.
- *The ten-vote rule stands* (2026-09-18).
- *A newly built route is outside what hone defends* (2026-09-18).
  [*Authority*](model.md#authority) says so. It closes the mock on `PATH`.
- *A public benchmark enters as a probe, never as a gate* (2026-09-19).
- *The review pin stays on opus* (2026-09-19). Sonnet matched its catches
  at a third of the price, with eight false alarms against none.
- *A lab fail in a part that a release does not touch does not block it*
  (2026-09-19), once someone has read it in its sandbox.
