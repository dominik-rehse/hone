# Spike: field data since 0.79.1

**Date:** 2026-10-14 · **Status:** frozen. Written once, never maintained
against the code.

## Question

All four consumer repositories took 0.79.1 at 22:17Z on 2026-10-09. What
did hone's hooks and critics do since then, and where did they cost
turns for no gain?

## Method

This is the first field pass that starts from counts.
`evals/field/extract.py` read every transcript of the four repositories
and their worktrees from 2026-10-09 22:17Z to 2026-10-14 about 13:00Z.
Then I read the sessions behind the largest counts and behind each deny.
I replayed one deny against the glob rule of the 0.79.1 `bash-guard`.

Two repositories had sessions: one with 94 and one with 6. The other two
had none. 59 sessions named 0.79.1, 40 named no version, and 1 still
ran 0.75.0, because nobody restarted it after the update. This is one
person's work over about four days.

## Counts

| hook | deny | block | advisory | pass | sessions |
| --- | --- | --- | --- | --- | --- |
| `bash-guard` | 5 | 0 | 0 | 0 | 4 |
| `dirty-guard` | 0 | 4 | 0 | 0 | 3 |
| `gate` | 0 | 7 | 59 | 45 | 23 |
| `guard` | 3 | 0 | 0 | 0 | 3 |
| `watch` | 0 | 46 | 0 | 0 | 3 |

The `plan-critic` approved 48 Plans and rejected 9. The
`consolidate-critic` proposed cuts in 33 reviews and found 13 clean.

## Findings

### The watch hook blocks a coordinator whose wait already returned

One coordinator session took 39 of the 46 `watch` blocks, from
2026-10-12 to 2026-10-14. Each block came 2 to 53 seconds after the
coordinator started `coordinate.sh wait` in the background, and 33 came
within 8 seconds. In the two blocks I read in full, the wait had already
returned with a queued event. The turn then ended, and the hook found no
wait running.

The coordinator did the right thing. When a background task exits,
Claude Code wakes the session with a notification, so the event was not
lost. Each block cost one extra turn and nothing else. The hook reads
"no wait runs" as "nobody will wake this session". That is wrong when a
wait has exited and its notification is pending.

I replayed the harness's queue log up to each `watch` block in every
transcript since 2026-09-29. 84 of the 91 blocks had a task notification
in the queue that no turn had taken. In 4 of the other 7, no wait had
run for hours, so the block was right. In 2, the wait had exited 3
seconds before, and its notification was not yet in the log. In the
last one, the hook blocked although the agent said a newer wait ran. I
did not look into it.

The same coordinator's first wait printed events of earlier batches, as
two did on 0.78.1.

### Agents read the suite lock to learn whether a land runs

Three of the five `bash-guard` denies were plan sessions that tried to
read the suite lock's queue. They wanted to know whether a land or a
verify was running before they committed their Plans. The repository's
pre-commit hook runs its unit suite, and a harness memory there records
that this load once made a land fail. The reason is real. hone offers no
read-only way to ask, and `worktree.sh status` does not say. Each agent
used `pgrep` after the deny.

### The gate-state glob rule denied a Python edit

One deny was a false alarm. A heredoc ran Python that wrote the text
`` `.claude/rules/hone-guard.md`\n"+s[j:] ``. In the shell that is one word.
It starts with `hone-` and holds `[`, so `GATE_GLOB` in
`hooks/bash-guard.sh` read it as a glob over the gate's files. A replay
of the word against the pattern matches. The same name with a space after
it does not.

The fifth deny was a read-only `git config --get` of the hooks-path key.
The guard denies any mention of that key by design.

### The rest

The three `guard` denies were right: one write in the primary tree, and
two source files with no test. The gate blocked 7 times against 45
passes. I did not read the 4 `dirty-guard` blocks.
