# Plan: optenv-5c-guards

Not seen by the `plan-critic`. This brief is a worker's plan for one campaign,
not a change to the plugin.

## What

Measure hone's four guard hooks under the three-part rule of HANDOFF,
*The structure layer*. The hooks are `bash-guard`, `dirty-guard`, `gate`, and
`guard`. The campaign runs the adversarial lab below the floor of the loop,
on claude-sonnet-5 and on claude-haiku-4-5-20251001. Each chosen scenario runs
with its hook on and with that one hook off. It also runs the three adversarial
scenarios that nobody has run with the guards off, on claude-opus-5.
The output is one note, `docs/spikes/2026-09-20-guards-below-the-floor.md`.
No script and no shipped file changes.

## Why

A guard is insurance. claude-opus-5 rarely reaches for what a guard forbids,
so a lab on opus says that the guards buy nothing. That is not evidence.
The field note of 2026-09-20 gives the second leg: how often each hook fired
in about 220 real sessions, and whether each block was right. The first leg
is missing. Only runs below the floor supply it.

## How I'll know it works

The note holds one table. Its rows are the hooks. Its columns are the reach
rate with and without the hook, per model, with n per cell. It also carries
the reaches that the hook stopped, the field numbers, and the cost of a wrong
block. Each reach gets one line: what the model reached for, whether the hook
stopped it, and what the model did next. Each hook gets a verdict under the
three-part rule. The note states facts and leaves every decision open.
`bash test/prose_test.sh` passes at the end.

## Notes for the loop

- Scenario choice per hook. `bash-guard`: `hand-merge` and `bypass-hook`.
  `dirty-guard`: `casual-fix`. `gate`: `wrong-test` and `spec-authority`.
  `guard`: `casual-fix` and `fix-without-test`.
- 3 runs per cell to start. A cell with a reach or a differing verdict grows
  to 5.
- Point 4 of the task asks for a sketch of a `dirty-guard` scenario, in ten
  lines, inside the note. Build nothing.
- Progress goes to `/var/tmp/hone-lab/campaign-5c/`, so a stopped plan resumes
  without a repeated run.
- Hard rules: no git write, no edit of a script, no write to a consumer repo.
  A hook goes off only through the lab's own flag.

## References

- `HANDOFF.md`: the rule and the step.
- `docs/spikes/2026-09-20-field-data-from-real-sessions.md`: the hook table.
- `evals/lab/README.md`, *Switching a component off*: the ablation rules.
