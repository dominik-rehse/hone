# Spike: what does the first section ablation of the critics show?

**Date:** 2026-09-17 · **Status:** frozen. Written once, never maintained
against the code.

## Question

The roadmap's stage 2 ends in a section ablation: delete one section of a
prompt, run its eval target, and cut what changes nothing. Which sections of
the two critic prompts does the suite hold today, and is any section ready
to go?

## What I did

Split each critic prompt into its top-level bullets, and the `plan-critic`
also into its *Calibration* paragraph. That gave 11 copies of
`agents/plan-critic.md` and 11 of `agents/consolidate-critic.md`, each with
one section deleted. Ran every visible case against every copy with
`--prompt-file`, at `--votes 3`, on claude-sonnet-5, which is the floor of
both critics. A control pass on the full prompt ran first. The
`plan-critic` had 9 visible cases and the `consolidate-critic` had 3. The
whole campaign made 432 calls and cost about 20 dollars at API prices.

The *Calibration* paragraph of the `consolidate-critic` introduces its
bullet list, so deleting it alone leaves a list with no head. I left that
copy out.

## Finding

Every deletion that flipped a plurality:

| prompt minus | case | full prompt | without the section |
|---|---|---|---|
| *Calibration* | `dep-refresh-no-red-test` | APPROVE 3/3 | REJECT 2/3 |
| *Calibration* | `named-references` | APPROVE 3/3 | REJECT 2/3 |
| *Prose doing an artifact's job* | `outcome-table-in-prose` | REJECT 3/3 | APPROVE 3/3 |
| *Slug collision* | `nested-slug-open-plan` | REJECT 3/3 | APPROVE 3/3 |
| *Contract churn* | `schema-silent-on-data` | `disposable` 3/3 | REJECT, no `disposable` |
| *A spike note doing a spec's job* | `spike-conclusion-only` | CUTS 3/3 | CLEAN 3/3 |
| single-caller helper (calibration) | `helper-single-caller` | CLEAN 3/3 | CUTS 2/3 |
| *A Decision that restates code* | `helper-single-caller` | CLEAN 3/3 | CUTS 3/3 |

So the suite holds four sections of the `plan-critic` and three of the
`consolidate-critic`.

Three readings go beyond the table.

- *The refresh bullet has lost its case.* `dep-refresh-no-red-test` aims at
  the *Dependency and toolchain refreshes* bullet. On 2026-08-27 the prompt
  minus that bullet rejected it 2/3. Today that copy
  approves 3/3, and the copy minus *Calibration* rejects 2/3. The current
  model no longer reads a missing red test as a placeholder, so long as
  *Calibration* tells it not to invent an objection. The bullet also rejects
  two refresh shapes, and no case aims at those. So the run does not clear
  the bullet for a cut. It says that the approving half may have expired.
- *A bullet also narrows its category word.* `helper-single-caller` has no
  Decision in it. Without the *Decision that restates code* bullet, all
  three votes filed the function's docstring under `decision-restates-code`.
  Each proposed to delete it. The word stays in the output list, and without
  its bullet nothing ties it to `docs/decisions/`. A cut of a bullet has to
  take its category word along, or the word floats.
- *The converse rule on spike notes still flips nothing.* The copy minus
  the calibration bullet on an aged spike note answered CLEAN 3/3 on
  `spike-note-may-age`, as the ledger already recorded.

Fifteen deletions flipped nothing. Seven are bullets of the `plan-critic`:
*Placeholders*, *Contradictions*, *Ambiguity*, *Missing baseline*, *Scope*,
*Collision*, and the refresh bullet. Eight are bullets of the
`consolidate-critic`. A case aims at two of the fifteen, the refresh bullet
and the converse rule, and the readings above cover both. No case aims at
the other thirteen, so under the reading rule the run says nothing about
them, and they stay. A single vote moved six times over the campaign: three
times on `thin-proof-right-level`, and once each on
`dep-refresh-no-red-test`, `named-references`, and `nested-slug-open-plan`.
That is inside the noise floor of the same day.

One case was at fault and not a section. `baseline-only-preserved` gave one
REJECT vote in 4 of the 12 `plan-critic` passes. Every such vote cited a
fork that the brief had by accident. I fixed the brief after the campaign.

## Where it landed

The ledger in `evals/README.md` carries the moved pins under
`dep-refresh-no-red-test`, `thin-proof-right-level`, and
`helper-single-caller`, and *Section ablation* there points here. The
campaign cut nothing. `docs/roadmap.md` stage 2 names the next step. It is
cases for the sections that no case aims at. It is also a REJECT case for
the refresh bullet, before anybody trims the approving half of that bullet.
