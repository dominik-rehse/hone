# Spike: field data since 0.58.1

**Date:** 2026-09-25 · **Status:** frozen. Written once, never maintained
against the code.

## Question

Between 0.58.1 and 0.60.0, hone changed land's rollback, the authority
gate's message, and how it reports a refused merge hook. Did those changes
hold in real sessions? What from this window is still open? This is a
narrower follow-on to
[the 2026-09-20 field note](2026-09-20-field-data-from-real-sessions.md),
not a replacement for it.

## Method

I read the Claude Code session transcripts of one private consumer
repository: 37 sessions from 2026-09-21 to 2026-09-25. 33 ran hone 0.58.1,
and 4 ran 0.59.0, from about 09:09Z on 2026-09-25. 26 of the 37 ran
`/hone:run`. Seven agents then read the transcripts and checked the
notable claims against the shipped code.

One repository, one person's work, five days. Nothing here says how hone
behaves for a second user, a second stack, or a longer window. A count
below comes from reading transcripts by eye, not a structured detector.
Read each one as a lower bound.

## Results by hook

### bash-guard

The primary-branch-move ask still misfires more than it catches: about 3
right calls against 11 false ones. False shapes include a directory change
into a scratch worktree before a merge there, and a path-scoped `git
reset`. Another is a checkout in a scratch clone addressed only by a
shell variable. One false ask sat 40 minutes before a person cleared it.
None of this has a fix yet.

New this window: the rule that protects a tracked check config also
catches a scratch `stryker.conf.json`, since the filename alone matches
the pattern. The ask does not name the file. Unattended runs stalled 7
hours, 81 minutes, 69 and 12 minutes, and 40 minutes on this ask, though the skill
says it runs isolated. Only one run actually put the config outside the
tree. Open.

### gate

The suite-lock block fired about 20 times naming "another session" as the
lock holder. The real holder was the session's own land, or its own
background verify. The block skips the retry cap the rest of `gate.sh`
uses, so an agent that hit this looped on turns with no visible output.
Open.

### nag

Three shapes repeat unchanged from the 2026-09-20 note. A `javascript:` or
`data:` link inside inline code still reads as real. A doc-over-cap
finding and a pending-Plans finding still repeat every stop, with no
action taken. New: a "survived its landing" false alarm fired three times
in one session, while its worktree was still legitimately open right
after a rollback.

### Progress lines

Not a hook, but a loop-wide finding. `skills/run/SKILL.md` asks for a line
at the start and end of each step. Of 23 finished runs, 10 printed fewer
than 5 of the 6 step-start lines. Five runs went quiet for 30 to 50
minutes with no line at all. Every landed run still printed `land ✓`, so
the loop itself worked, it just did not narrate. A likely cause, not
verified: the rule appears once near the top of the skill, and only the
verify section repeats it. Open.

### Land, the authority gate, and the proof gate: fixed since 0.58.1

Four defects from this window are already fixed:

- Land's rollback used `git reset --hard` on the primary tree, which twice
  dropped a concurrent Plan's own commit from main. A branch later cut
  from the dropped commit caused a false exit 8. **Fixed in 0.60.0**: land
  now verifies the merge in the worktree first, then fast-forwards.
- Land's receipt once named the wrong commit as the merge. **Fixed in
  0.60.0**, by the same change.
- Post-merge checks in the primary tree read other sessions' untracked
  draft Plans, causing at least 6 spurious rollbacks. **Fixed in 0.60.0.**
- Exit 9 reported a refused pre-merge-commit hook as a merge conflict.
  **Fixed in 0.59.1.**

One is partly addressed. The authority gate, exit 8, fired 3 times and
caught nothing real. Twice it fired on SQLite's table-rewrite idiom (new
table, copy, drop, rename). Once it was a false alarm from the rollback
bug above. **Partly addressed in 0.60.0**: the refusal now quotes
each destructive statement with its file, though it does not cut the
SQLite false-fire rate.

0.60.0 fixes two smaller ones too. The proof gate once named a probe
script for the wrong change, and that script did not exist. Land run from
inside its own worktree used to exit 2 after a successful merge. It could
also refuse to remove the worktree when given a change name or a relative
path.

One fix opened a gap. `skills/garden/SKILL.md` still reads every land exit
6 as "the cut was unsafe," but since 0.59.1 a refused merge hook also
exits 6. Open.

## Critics

`plan-critic` and `consolidate-critic` still catch real problems:

- a wiki-write move that skipped required checks.
- a route exposed on the tailnet.
- a false concurrency claim risking real data loss.
- a Proof trailer with no matching probe.

Two gaps recur. `plan-critic` approved a Plan twice whose Proof trailer
needed a probe script keyed by the change's slug. No such script existed
either time. Land then failed the proof gate both times.

`consolidate-critic` proposed three cuts a person had to decline:

- dropping a required `MutationObserver`.
- cutting a test and a sentence that nested review then asked restored.
- cutting content outside the diff, which another Plan had ring-fenced.

One `plan-critic` review took four rounds on a one-paragraph docs Plan,
each reject naming a real contradiction the previous fix had introduced.

Verdict formatting drifted on 0.58.1: a bolded verdict, a "Verdict:"
prefix, prose after the verdict, a file list last. It was clean on the
small 0.59.0 sample, too small to call fixed. On 0.59.0, both
critics missed that a CLI upgrade had made a stated Decision false.
Nested review caught it instead.

## Human attention

About a dozen runs landed with no human turn at all. Where the loop
needed a person, it was mostly for the right reason. The proof gate
stopped a sign-off nobody could run. A critic's plan-mode deny and
wiki-write catch also justified it.

Two shapes cost attention without earning it. A Sonnet main session twice
retried land blindly after an exit 9 or exit 6. Once this went against
`land.md`'s own "stop and escalate," citing a memory file instead of the
doc. `/hone:plan` fired once when the person had asked for a chat handoff
instead ("No, don't plan"). One session also created and landed an
unplanned worktree after the person said "You do it." Twice the person
had to ask the agent to speak plainly.

One session was missing the SessionStart workflow-rule injection every
other plugin's session carried that day. The cause is not known.

## What went well

Land rollbacks kept main green. Every `guard` fire was right, and no agent
reached for a sabotage token. The person used the off marker once, and
cleared it cleanly. The proof gate forced a real on-box probe. In doing
so, it turned up a real `EACCES` bug in the consumer's proof script, and a
real port collision. The agent's own note on that run reads "I did not
weaken the probe."

Nested `/code-review` found a real bug in nearly every run it touched:

- a login where a tab or newline could forge an owner row.
- a leaked `ZodError`.
- a root helper that followed a planted symlink.
- a `ROLLBACK` that masked `SQLITE_FULL`.
- a dismissed alert that rang again.

On the small 0.59.0 sample, critics ran in 6 to 13 tool calls instead of
13 to 43. They still found real defects, and put the verdict on the last
line every time.

## What it means

Together, 0.59.1 and 0.60.0 fixed five real defects from the 0.58.1
window:

- land's rollback and its receipt.
- the post-merge read of other sessions' drafts.
- the exit-9 misreading of a refused merge hook.
- the proof gate's wrong probe name.
- land run from inside its own worktree.

The authority gate's message is clearer. Its false-fire rate is only
partly addressed, since the SQLite-idiom shape behind two of its three
fires is not itself resolved.

Everything else here is still open:

- the bash-guard primary-branch-move false rate.
- the scratch mutation-config stall.
- the suite-lock misattribution.
- the three repeating `nag` shapes.
- the missing progress lines.
- the critic's proof-probe gap.
- garden's new exit-6 ambiguity.

A few already have fixes in progress. None of it counts as fixed by
anything later than 0.60.0, since nothing later than 0.60.0 had shipped
when this window closed.

This window is short and one-sided: one repository, five days, read by
hand rather than by a structured detector. Read every count here as "at
least," not as exact.
