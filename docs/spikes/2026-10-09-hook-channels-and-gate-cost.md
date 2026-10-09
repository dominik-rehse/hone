# Spike: which reader a hook reaches, and what the gate costs

**Date:** 2026-10-09 · **Status:** frozen. Written once, never maintained
against the code.

## Question

hone's hooks talk to two readers: the model and the person. Which output
channel reaches which reader? And how much time does the gate spend at the
end of each turn?

## Method

Channels: a throwaway repository with one hook that printed a secret word.
I asked the model in a later turn whether a hook had named a secret word.
I started the same project in an interactive session under tmux and read
the screen. Claude Code 2.1.295, haiku and opus.

Gate cost: the Stop-hook attachments in the transcripts of four consumer
repositories, which record each hook's command, output, and duration.

## Results

Which reader gets a hook's output:

| hook | output | the person | the model |
| --- | --- | --- | --- |
| Stop | `systemMessage` | yes | no |
| SessionStart | plain stdout | no | yes |
| SessionStart | `additionalContext` | no | yes |
| SessionStart | `systemMessage` | yes | no |
| SessionStart | both fields in one object | its part | its part |

A Stop hook's `{"decision":"block"}` reason reaches the model. That is how
the gate's failures reach it.

So the nag's findings reached only the person, and an unattended run read
none of them. hone's session-start warnings asked the person to act, but
only the model got them.

The gate in the largest repository:

| what ran | runs | total | average |
| --- | --- | --- | --- |
| unit tests, type-check, lint | 613 | 8.8 h | 51 s |
| full suite (backstop) | 55 | 4.1 h | 4.5 min |
| killed at the 600 s hook limit | 12 | 1.7 h | 10 min |
| skipped on a green receipt | 129 | 0.1 h | 3 s |

- 358 of the 613 unit runs followed a turn with no file edit since the
  previous gate run. 27 had no tool call, and 331 had shell commands only.
- 22 times the gate gave up only after it had blocked several turn ends in
  a row on a held suite lock. Often the holder was the run's own background
  verify or land.
- A killed gate lets the turn end, so those 12 runs checked nothing.
- The other three repositories spent 3 to 70 minutes on the gate in total,
  at a median of 10 to 28 seconds.

In 371 of 683 lands across the four repositories, `main` had not moved since
the branch was cut. Land still reruns the suite, because consolidate edits
the tree after verify, so the merged tree differs from the verified one.

## What follows

- A message must use the channel of the reader who acts on it.
- Findings for the run belong in a command the run calls, as
  `worktree.sh complexity` does. Findings for the person belong at session
  start and in the final report.
- The gate can skip a check whose input did not change. The full suite
  belongs in verify and land, which have no hook time limit.
