# Spike: which critic sections does the suite hold on opus?

**Date:** 2026-09-18 · **Status:** frozen. Written once, never maintained
against the code.

## Question

The [first section ablation](2026-09-17-first-section-ablation.md) ran on
claude-sonnet-5. The critics run on claude-opus-5 since 0.54.0. Which
sections does the suite hold on the new pin, and is any section ready for a
cut?

## What I did

Made one copy of each critic prompt per section, with that section deleted.
A section is a top-level bullet, and for the `plan-critic` also the
*Calibration* paragraph. That gave 11 copies per critic. Ran every visible
case against every copy with `--prompt-file`, at `--votes 3`, on
claude-opus-5. A control pass on the full prompt ran first. The
`plan-critic` has 8 visible cases and the `consolidate-critic` has 3. The
campaign made 396 calls and cost 33 dollars at API prices. The copies, the
logs, and the `--json` records are in `/var/tmp/hone-ablation-20260918/`.

Two more runs followed. Each took one copy and also deleted the category
word of the bullet from the *Output* list. Each ran the one case that aims
at the bullet, at three votes.

## Finding

The control passed every case at 3/3. Every deletion that failed a case:

| prompt minus | case | full prompt | without the section |
|---|---|---|---|
| *Calibration* | `thin-proof-right-level` | APPROVE 3/3 | REJECT 3/3 |
| *Contradictions* | `thin-proof-right-level` | APPROVE 3/3 | REJECT 2/3 |
| *Missing baseline* | `thin-proof-right-level` | APPROVE 3/3 | REJECT 2/3 |
| *Missing baseline* | `schema-silent-on-data` | `disposable` 3/3 | REJECT, no `disposable` |
| *Contract churn* | `schema-silent-on-data` | `disposable` 3/3 | REJECT, no `disposable` |
| *A spike note doing a spec's job* | `spike-conclusion-only` | CUTS 3/3 | CLEAN 3/3 |

Four readings go beyond the table.

- *Opus needs less of the prompt than sonnet did.* On sonnet, the copy
  minus *Calibration* rejected `dep-refresh-no-red-test` and
  `named-references`. On opus it approves both at 3/3. On sonnet,
  `helper-single-caller` flipped without the bullet *A Decision that
  restates code* and without its calibration bullet. On opus it stays CLEAN
  at 3/3 in both copies.
- *The category word does the work of its bullet.* Two copies still
  rejected their cases at 3/3, under the right category. They are the copy
  minus *Slug collision* and the copy minus *Prose doing an artifact's job*.
  The word was still in the *Output* list. With the word deleted too,
  `nested-slug-open-plan` flipped to APPROVE 3/3. `outcome-table-in-prose`
  stayed REJECT 3/3 for its other faults, and no vote named
  `missing-artifact`. So the suite holds both bullets. A cut must take the
  word along, as the first campaign said.
- *`thin-proof-right-level` stands on an edge.* One vote of three rejected
  it in three more copies. They are the copies minus *Placeholders*, minus
  *Collision*, and minus *Slug collision*. None of those bullets is about a
  proof. The control and the noise floor of the same day had it at 3/3. So
  the case moves with any shorter prompt, and a flip on it says little
  about the deleted section. Only the 0/3 without *Calibration* is clear.
- *The rest moved nothing.* *Ambiguity*, *Scope*, and the refresh bullet
  of the `plan-critic` changed no tally. Neither did ten sections of the
  `consolidate-critic`. A case aims at one of them, the refresh bullet, and
  only at its approving half. The first campaign's reading of it stands.
  Under the reading rule the run says nothing about the others.

## Where it landed

No section is ready for a cut. On opus the suite holds five sections of the
`plan-critic`: *Calibration*, *Missing baseline*, *Contract churn*, *Slug
collision*, and *Prose doing an artifact's job*. It holds one section of the
`consolidate-critic`. `docs/roadmap.md` no longer lists the campaign as owed.
It lists what a cut still needs, which is a case that aims at the section.
