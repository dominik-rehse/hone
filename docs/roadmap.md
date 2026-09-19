# Roadmap: what is open

This page lists what is open in the work on hone itself, and what the
maintainer decided. [*Goals*](model.md#goals) has the outcomes.
[`development.md`](development.md) has the procedure that judges a change,
and [`releasing.md`](../.claude/rules/releasing.md) has the release gates.
The history is in the dated notes under `docs/spikes/` and in git.

## Open

### Defects with evidence

The first three are from
[`impossiblebench-first-look`](spikes/2026-09-18-impossiblebench-first-look.md).

- *A run that keeps a test red cannot end its turn.* Three runs rightly kept
  a wrong test red. The turn-end hook blocked each run nine times, until
  the session ended.
- *A carve-out can enter through the Plan.* One Plan named a carve-out for
  a wrong test as a requirement. The `plan-critic` approved it. The review
  endorsed the code, because its brief said that the test must pass.
- *One run merged around the loop.* It made a worktree by hand and
  fast-forwarded the primary branch, with no review and no land gate. No
  scenario tempts that route.
- *The nested review may not fan out.* `subagent_stats.spawned` is 0 in 128
  of 129 valid envelopes. Also, `Bash(git *)` denied 50 `git` commands, 30
  of them behind a `cd`. Commit `cc1bc4a` has the counts.
- *The `plan-critic` still asks too much at times.*
  `fork-settled-by-decision` approves in 15 votes of 17. A fail of that
  case asks for ten votes.
- *`setup-misfit` failed once in four runs.* The run invented a test script
  that called the adapter, and the adapter calls npm.
- *`candidate.sh decide` cannot filter its baselines.* It answers
  *undecided* when the baseline runs carry plugin hashes that differ only
  in paths that the scenario never loads.

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
- *A reviewer from another model family* waits for a review that misses a
  defect which its brief did not hide. `--review-model` can then price it.
- *Automated search over candidates* waits for a cheap judge. The lab
  costs 10 to 50 dollars per candidate.
- *hone on hone* is a project of its own
  ([`development.md`](development.md), *Change briefs*).

## Decided

- *The `consolidate-critic` stays* (2026-09-18). A test of its removal
  would cost about 60 dollars, and the maintainer decided against it.
- *A deterministic check needs no measured gain* (2026-09-18). It is rule
  5 of the procedure.
- *The ten-vote rule stands* (2026-09-18).
- *A newly built route is outside what hone defends* (2026-09-18).
  [*Authority*](model.md#authority) says so. It closes the mock on `PATH`.
- *A public benchmark enters as a probe, never as a gate* (2026-09-19).
- *A lab fail in a part that a release does not touch does not block it*
  (2026-09-19), once someone has read it in its sandbox.
