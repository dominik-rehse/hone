# Spike: what does the optimization record hold up to, read with the method in hand?

**Date:** 2026-09-18 · **Status:** frozen. Written once, never maintained
against the code.

## Question

`docs/roadmap.md` recorded what earlier sessions built and measured toward
the optimization of hone. That record came before the outcomes were written
down. The method of the roadmap now exists. Which measurements does it
keep? Which does it make obsolete? And what did the record get wrong?

## What I did

Built the method first: the measures, `revertible`, the ending, the two
seeded scenarios, and `evals/candidate.sh`. Then read the record in
`docs/roadmap.md`, both eval manuals, and the five notes of 2026-09-17 in
this directory. Made no model call. Regraded the kept full pass
`/var/tmp/hone-lab/20260917-223323` on a copy, with a fake judge, to see the
new fields on real end states.

## Finding

### What the method keeps

- The discrimination rule of the unit suite, with both baselines, and the
  held-out cases. They are why a green suite means something, so they are
  the constraint of every candidate.
- The three-valued verdict of the lab, `--regrade`, `--without`, and
  `--review-model`. The two notes of `review_named` became the measures
  `review_named` and `brief_named`, so a tool can count them.
- The measured floors per slot. They became `evals/floors`.
- The three classes of building blocks and their evaluators.
- The rule that a cut of a bullet takes its category word along.
- The habit of counting the reach beside the verdict in `casual-fix`. It is
  still a command that a person runs by hand. A measure `reached` would let
  the procedure count it.

### What the method makes obsolete

- *The rule that a cut needs an unmoved tally.* On an unchanged prompt,
  single votes dissent. The noise floors saw 5 of 171 and 1 of 216. So one
  vote of three is no evidence. The method decides a moved tally at ten
  votes.
- *The goal of stage 1, a case for each section.* Two passes showed that a
  CUTS case and a REJECT case pin a category word at best. A model with no
  hone prose finds the same fault when a brief hands it over. Thirteen of
  twenty critic sections have no case, and more briefs will not change
  that. The method asks another question of such a section: does
  the run leave a worse codebase without it? The lab answers that with the
  seeded scenarios, for a group of bullets or for a critic as a whole.
- *The stages as the plan.* Stages 0, 2, and 3 are done, and the two
  manuals and these notes carry what they built. The roadmap repeats them.
- *Automated search, for now.* A candidate that needs the lab costs 10 to
  50 dollars to judge. So a search over many candidates is not affordable.
  A search at the unit level is affordable, and the record shows that the
  unit level pins little. An optimizer would be one more source of
  candidates for `evals/candidate.sh`.

### What the record got wrong, or what went stale

- *It read an undiscriminating case as expired prose.* Stage 1 concludes
  that many sections with no case are "prose that the model no longer
  needs". The measurement does not show that. It shows that a bare model
  cuts a repeat of the code when a brief contains it and asks for a
  verdict. In the loop nobody hands the run such a brief. The run must
  notice by itself that a change made a sentence false, in a document that
  it never opened. Whether the consolidate step and its critic make that
  happen is unmeasured until `seeded-prose` runs. The conclusion may still
  be right. Then the whole `consolidate-critic` is a candidate for removal,
  and it saves a subagent call in every change.
- *The section ablation measured a model that no longer runs the critics.*
  It ran on claude-sonnet-5, which was the pin on 2026-09-17. The pin moved
  to claude-opus-5 a day later. `evals/README.md` already says that three
  of the near-miss cases pin nothing on opus. So "the suite holds four
  sections of the `plan-critic`" is a statement about sonnet. A cut of any
  critic section needs the campaign again on opus, about 10 dollars per
  critic.
- *The record applied the floor rule to pinned slots.* A critic runs on
  its pin for every user, whatever model drives the session. So the rule
  means something only for the slots that run on the session's model.
  Those are the loop, plan, and garden.
- *The floor rule points the wrong way for a guard.* `casual-fix` shows a
  guard at work only on haiku and sonnet, which are below the floor of the
  loop. Opus never reached in three runs. On the floor model the lab still
  has no scenario that shows the value of any guard. A guard defends the
  user who runs a cheaper model than hone recommends. So a candidate that
  touches a guard is measured below the floor, and the method now says so.
- *The release rule cites a noise floor that the record itself withdrew.*
  `.claude/rules/releasing.md` said "24 passes out of 24". Those 24 runs
  had hone's development rules in context. The clean number is one pass of
  11 out of 11.
- *The outcomes section called a decision a gap.* It said that hone has no
  step that looks for duplicated logic across the codebase. *Types and
  abstractions* in `docs/model.md` rejects such a step on purpose. The gap
  that does exist is narrower: nothing turns an existing prose fact into a
  type when a change touches it.
- *The counts are small everywhere.* The guard table has one to three runs
  per cell, and the reviewer table has two per model. The record says so
  each time. Under the method none of those tables can accept or reject a
  candidate, because a measure needs three runs per arm.

### What the regrade showed

All eleven kept runs still pass. `revertible` holds on the kept
`happy-path` run. The three stopped runs get `stop_actionable`. Each of the
eight landed runs has an ending that names its branch, its commit types,
and its places. Four of them wrote to `docs/open-questions.md`.

## Where it landed

`docs/development.md` carries the method. The record section left
`docs/roadmap.md`, because the notes in this directory and the two eval
manuals carry what it held. `evals/floors` carries the floors and the
exception for a guard. `.claude/rules/releasing.md` cites the clean noise
floor. `docs/roadmap.md` lists what is open. The seeded scenarios ran, and
the maintainer decided to keep the `consolidate-critic`.
