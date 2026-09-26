# Spike: closing the bash-guard holes, replayed on real commands

**Date:** 2026-09-26 · **Status:** frozen. Written once, never maintained
against the code.

## Question

The `bash-guard` of 0.63.0 let some real moves of the primary branch or
HEAD pass (see the roadmap). A new last rule runs the analysis on any
command that names a guarded command or a push, and can ask. How many new
asks does that add on real work, and are they right?

## Method

I took every Bash command from the Claude Code transcripts on this machine
that names a git move, a push, a package install, or a formatter, and
whose directory still exists: 639 distinct commands across the hone repo,
four consumer repos, and two other repos. Each ran through the 0.63.0 hook
and the new one, with the recorded shell directory. The file system is
today's, not the one at the time, so a scratch path that is gone reads
differently. One machine, one person's work.

## Results

A first version asked whenever the analysis could not model the command.
It added 33 asks. 28 were false: a push to the team's remote inside a
`for` loop, a Python heredoc whose text names `checkout`, a release
command with a heredoc message.

The final version asks only when the analysis finds a move in the
primary tree, or when a runner such as `sudo`, `env`, or `bash -c` hides
the tree of a guarded command. It adds 5 asks, and all 5 are right. Each
ran in a subdirectory of a primary tree: `npm install -D <pkg>`,
`git stash push -u`, and a `git checkout <file>` without `--`. The old
rules missed them because `hone_is_primary_tree` compared an absolute
`--git-dir` with a relative `--git-common-dir`.

The same work found that rules 3, 3a, and 3b did not accept `git -C
<path>` before the subcommand, so `git -C <primary> checkout <branch>`
from a worktree passed. The new rule asks on it.

## Run time

A 7 KB command of 160 simple commands (cds, `git -C`, variables, a push)
took a median 2.1 s on the new hook and 2.2 s on 0.63.0, over five runs
each. A 2.7 KB command took about 1 s on both. The hook's timeout is 5 s.
