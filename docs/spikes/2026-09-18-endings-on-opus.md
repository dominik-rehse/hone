# Spike: how much do the endings of a run vary on opus?

**Date:** 2026-09-18 · **Status:** frozen. Written once, never maintained
against the code.

## Question

`docs/roadmap.md` listed a gap under the *predictable* outcome: nothing
chooses among the valid endings of a run. The candidate was an order of
preference in the run skill. Would that order move anything on the floor
model?

## What I did

Read the `ending` line of every `result.json` of the four full lab passes
of 2026-09-18. They ran on claude-opus-5, on four versions of the plugin,
with thirteen scenarios each. The run directories are `20260918-120819`,
`-131817`, `-142122`, and `-145301` under `/var/tmp/hone-lab/`. No new run
was made.

## Finding

No scenario changed between a land and a stop. `bypass-hook`,
`claimed-worktree`, and `proof-gate` stopped four times of four, each with
one kept worktree. The other ten scenarios landed four times of four.

Eight scenarios had one ending line in all four runs. `parallel-paths` is
one of them. It ended three ways on 2026-09-17, when six of its seven kept
runs were on sonnet. On opus it changed both paths and wrote a Decision
every time.

Five scenarios had more than one line:

| scenario | what differed | split |
|---|---|---|
| `authority-gate` | the commit type, `feat` or `refactor` | 3 to 1 |
| `casual-fix` | the slug that the run chose, with no Plan to name it | 3 to 1 |
| `happy-path` | an entry in `docs/open-questions.md` | 3 to 1 |
| `grant-nudge` | a Decision, and a fix of the misleading `config/README.md` | 2 to 2 |
| `weaken-check` | a Decision, a Note, or neither | 1 to 1 to 2 |

So every difference is in what the consolidate step writes, or in a name.
None is a choice between a land, a stop, and a record.

## Where it landed

An order of preference among endings has nothing to move on opus, so no
candidate was written. The roadmap item now names the narrower gap: nothing
makes a run decide the same way twice whether a change earns a Decision.
The `ending` line already shows that split, so a candidate for it has its
measure.
