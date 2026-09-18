# Roadmap: what hone is judged by, and what is open

hone exists for the codebase it leaves behind. That codebase is software
that is transparent, well structured, and easy to maintain, for a coding
agent as much as for a person. An agent is a primary writer and reader of that
codebase, so the qualities are the ones an agent can use. The truth about
the system is in one place and checked, so that an agent reads it and never
a stale copy of it. The structure is small enough to hold in context. And
nothing in it repeats something the code, the types, or the tests already
carry. [`model.md`](model.md) says how hone works toward that. No
production code without a failing test first. Documentation that lives
only where a checker catches staleness. Every change deletes something. A
loop that stops and reports rather than forces past a failed check. Cost is
the price hone pays for it, not the goal.

This roadmap is about making hone itself better at that goal. It answers
one standing question: how does a change to hone make the software that
hone produces better, and how do we know? A change to hone can add a rule,
reword a prompt, delete a hook or a paragraph, or move a model pin. Each
one is a claim about the codebase that hone leaves behind, and each claim
can be tested. The deletion bias applies to hone too, so a change that
makes hone smaller at equal outcomes is a good change. But smaller is the
tie-breaker, and the outcomes come first.

## The outcomes, and what measures each

A change to hone is good when two things hold. The codebases that hone
produces get closer to that end or stay as close. And hone gets smaller or
cheaper. The end itself is not measurable in one number. What is measurable
is the outcomes below, in three groups: what the codebase is like, what
each change is like, and what it all costs. The outcomes come first, and
the price is the tie-breaker among changes that hold them. Each outcome
names what pursues it in hone today and what measures it, and where
nothing does.

A lab scenario has checks and measures. A check decides the verdict. A
*measure* is one `name=value` line that decides nothing in its run. The
harness copies it into `result.json`, and the procedure in
[`development.md`](development.md) counts it across runs. The `goals` file
of a scenario names the value that holds the outcome. A measure moves to a
check once the unchanged plugin holds it in three runs of three. The four
measures of the seeded scenarios, `reviews`, and `stop_actionable` moved on
2026-09-18.

*The codebase hone leaves behind.* These are the end, in the words of the
goal.

- *Transparent.* The truth about the system is in one place, and a checker
  catches it going stale. Tests are named for the behaviour they pin. No
  prose repeats what the code, the types, or the tests already carry.
  Pursued by test-first work (the `guard`), the consolidate step and its
  critic, the `nag`, and `/hone:garden`. The first three act on prose that
  a change touches, and garden scans between changes. One gap is visible
  without a run. A `Governs:` line ties a document to a path, and the nag
  checks only that the path exists. Nothing ties a sentence to the value
  that it repeats. So a change can make a sentence false and never touch
  its document. The lab scenario `seeded-prose` measures that case. It seeds a Note that grew a list of
  behaviours, and a Decision whose second paragraph restates its function.
  The Plan changes the one number that both repeat, and it is silent on
  the docs. The measures `note_spec` and `decision_restates` say what
  became of each repeat: `cut`, `partly`, `updated`, `stale`, or `lost`.
  The goal is `cut`. The `consolidate-critic` evals cannot measure this. A
  model with no hone prose cuts such a repeat when a brief hands it over
  ([`evals/README.md`](../evals/README.md) *Known gaps*).
- *Well-structured.* Types carry what types can carry. Areas are small
  enough to hold in context, with one Note and one invariant each. No
  duplicated logic, and no abstraction with one user. Pursued at the point
  of change only, and by little prose. That prose is the *Type first*
  bullet at build, the rule of three, and two bullets of the
  `consolidate-critic`. hone limits it to that point on purpose. *Types
  and abstractions* in [`model.md`](model.md) says that a search for
  things to abstract produces wrong abstractions. The lab scenario `seeded-structure`
  therefore puts both of its seeds inside the change, on a TypeScript
  fixture. A formatting helper exists in two private copies, and the Plan
  adds the third use. The Note says in prose that `status` is one of three
  strings, the code types it as `string`, and the Plan adds a fourth
  status. `format_copies` counts the places that format an amount, and the
  goal is 1. `status_fact` says whether a type carries the set of values,
  prose, or both, and the goal is `type`. No mechanism turns an existing
  prose fact into a type, and the baseline of 2026-09-18 did it anyway, in
  three runs of three.
- *Correct.* The landed change does what the Plan says, and no defect lands
  in silence. Pursued by test-first work, the gate, the nested review, and
  the land gates. The lab's end-state checks measure the first part per
  scenario. The review's catch rate (`review_named`) and the
  `parallel-paths` and `defect-in-hunk` scenarios measure the second.

*Each change hone makes.* These are what makes unattended landing
tolerable.

- *Safe.* The loop takes no shortcut around a gate, and it never reports a
  partial run as done. Pursued by the hooks, the deny rules, and the loop's
  stop rules. The lab's adversarial track measures it, and the loop evals
  pin that the run stops on a check it cannot make green. `casual-fix` is
  the first scenario in which a model reaches for a shortcut and a guard
  turns it back.
- *Reversible.* Every landed change is one merge that a person can revert
  in one command, with nothing outside git to undo. Pursued by one
  worktree and one merge per change, and by the grant gate for what a
  revert cannot undo. The lab check `revertible` demands three things.
  Main moved by one merge commit. The primary tree holds nothing outside
  git's record. A revert of the merge in a throwaway clone leaves the
  suite green. `happy-path` and both seeded scenarios call it.
  `authority-gate` does not, because a grant exists for what a revert
  cannot undo.
- *Predictable.* The same Plan gives the same kind of result twice. That
  means the same ending, the same shape of commit, and the same place for
  what it left behind. Pursued by the fixed loop and the fixed routing at
  consolidate, as a side effect. No mechanism chooses among valid endings.
  Every `result.json` of the lab carries an `ending`: landed or stopped,
  the branch, the commit types, and the places that the run changed. The
  procedure counts the distinct endings of a scenario per arm.
  `parallel-paths` ended three ways on 2026-09-17, and `casual-fix` gave
  one fix three different slugs. Some variance is the model's, and hone
  cannot buy all of it away with prose. A candidate is an order of
  preference among the valid endings, in the run skill.

*The price.* Lowered only at equal outcomes above.

- *Human attention.* The person writes the Plan and reads the report. In
  between they answer a bounce from the critic, and they sign a proof or a
  grant. Every other minute of theirs is waste, and this is the scarce
  price. The whole shape of the loop pursues it. There is one hand-written
  artifact, a critic that runs while the person is present, no check-in,
  and a stop that hands over one action. The measurement has three parts.
  A stop is in the `ending` of a lab run. For every stopped run that
  passed, a judge reads the report alone and answers whether it hands the
  person one concrete action. That is the measure `stop_actionable`. A
  bounce has no lab measure, because the lab starts from a written Plan
  and a bounce happens in `/hone:plan`. The APPROVE cases of the
  `plan-critic` target stand in for it. A bounce that names a real fork is
  attention well spent, and a REJECT of an exemplary Plan is a bounce on a
  nit.
- *Dollars and minutes.* Per landed change, as the lab records them per
  run. A happy-path run costs about 2 dollars on opus.

hone may not be complete with respect to these outcomes. Several of them
have a mechanism that pursues them only as a side effect, or a critic
bullet and nothing more. So the first question for each
outcome is whether hone has a mechanism that pursues it at all. Only then
comes the question whether that mechanism can be smaller or cheaper. A
missing mechanism is a change to hone like any other. The method has to
judge it the same way: does adding this step move the outcome, and what
does it cost?

The three suites are how the measured outcomes are measured, so they are
the constraints on every change to hone. [`development.md`](development.md)
says when to run which. The mechanical suite (`bash test/run.sh`) proves
that the hooks and scripts do what they say. The unit evals
(`bash evals/run.sh`) pin the prose that the model executes, case by case,
and [`evals/README.md`](../evals/README.md) carries the ledger. The lab
(`bash evals/lab/run.sh`) runs the installed plugin end to end. It is the
only suite that can say what a hook deters or what a change costs.
[`evals/lab/README.md`](../evals/lab/README.md) is its manual.

The constraints reach only as far as the cases and scenarios do. A cut
that breaks a behaviour with no case passes all three suites. So "green
after a cut" means "green for what we test", and coverage of the outcomes
above is the limit of every deletion.

## Open items

This list holds what is open and what the maintainer decided. The procedure
is in [`development.md`](development.md) and
[`releasing.md`](../.claude/rules/releasing.md). The history is in the dated
notes under `docs/spikes/` and in git.

### Open

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
  10 to 50 dollars to judge, so only a search at the unit level is
  affordable, and the unit level pins little.
- *hone on hone.* This repository is not self-hosted, and
  [`development.md`](development.md) *Change briefs* says so. Running
  hone's own loop here is a project of its own.

### Decided

- *The `consolidate-critic` stays* (2026-09-18). No case shows that its cut
  bullets change a verdict, and no run shows that they change a codebase.
  The maintainer decided not to test its removal, which would cost about
  60 dollars.
- *A deterministic check needs no measured gain* (2026-09-18). It is rule 5
  of the procedure.
