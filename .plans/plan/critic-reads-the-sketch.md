# Plan: plan/critic-reads-the-sketch

## What
`/hone:plan` hands the `plan-critic` the Plan, the open changes, and the
relevant Decisions and Notes. It does not hand over the sketch. So the critic
judges the Plan alone, and a fork that the author closed while writing the
Plan is invisible to it. Hand the sketch over verbatim beside the Plan. The
critic's *Ambiguity* rule then rejects a Plan that settled a fork the sketch
left open, where the repository settles nothing.

## Why
The lab scenario `plan-fork` failed three runs of three on claude-opus-5. Each
run picked a side, committed the Plan, and handed it to an unattended run. The
critic approved every time. One run named the fork in its own report and
committed anyway. One critic called it "the single genuine fork", and it
approved because the Plan had decided it. The person pays for that with a
change built the way they did not choose.

## How I'll know it works
The outcome is *human attention*, and the measure is `bounced`.

- Lab `plan-fork`, three runs on claude-opus-5: `bounced` is yes.
- Lab `plan-clear`, three runs on the same model: `bounced` stays no. The
  counter-risk is a critic that now asks about every open detail.
- `bash evals/run.sh plan-critic --votes 3` stays green, with one new case,
  `fork-closed-by-author`: a Plan that closes a fork its sketch left open.
  The case discriminates under `--ablate`.

## Notes for the loop
- The `plan-critic` has not seen this brief.
- Shipped files: `skills/plan/SKILL.md` step 6 and the *Ambiguity* bullet of
  `agents/plan-critic.md`.
- No consumer state changes. The brief is built per session, so no repository
  holds the old shape.
- The reject path stays as it is, on purpose. Step 6 already sends the
  findings back to the caller. Step 4 already says that a question for the
  caller is never an open question. Add prose there only if the runs show a
  second attempt that picks the other side.
