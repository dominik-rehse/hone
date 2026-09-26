# Spike: the bash-guard fails closed where its analysis gives up

**Date:** 2026-09-26 · **Status:** frozen. Written once, never maintained
against the code.

## Question

Rule 5 of the 0.64.0 `bash-guard` asked only when its analysis found a move
in the primary tree. The analysis stops reading at a loop, a branch, or a
function, so a `cd` into the primary tree there passed, and so did the
merge after it. The change makes rule 5 read that part without order, and
ask on anything it cannot place. What does that cost, and how long does it
take?

## Results

Shapes, each run from a linked worktree through 0.64.0 and the new hook.
Every one of these passed on 0.64.0 and asks now:

- a `cd <primary>` inside a `for`, `while`, `if`, or `case` body, or in a
  function, then `git merge`
- `git -C "$d" merge` with `d` a loop variable that names the primary tree
- `sudo git merge`, a `git branch -f main`, and an `eval "cd <primary>"`,
  each inside a loop
- a push in a loop from a clone whose origin is the primary tree
- a `cd` to an unset variable, or to one set by `read`, inside a loop

The same shapes with a scratch worktree in place of the primary tree pass,
and so do a loop of pushes to another host, a loop of `git checkout --`
restores in the primary tree, and a harmless loop after a merge in a
worktree.

The copy change: 10 copies that only read an adapter asked on 0.64.0 and
pass. 5 copies that write one by its directory, or with `-t`, passed on
0.64.0 and ask. Across both changes, 28 new tests in `test/hooks_test.sh`
fail on 0.64.0.

## Run time

Median of five runs, on this machine. A 7 KB command of 160 simple
commands (cds, `git -C`, variables, a push) takes 1.1 s on both hooks. The
same command behind a `for` loop takes 1.75 s on the new hook and 1.05 s
on 0.64.0, because the new rule reads all of it again without order. A
loop of 40 relative cds stops at 64 directories and asks, in 0.15 s. The
hook's timeout is 5 s.

## Not measured

The replay of the 639 real commands of
[the note before](2026-09-26-bash-guard-holes-replay.md) did not run. It
reads the Claude Code transcripts on the maintainer's machine, and this
session was refused that read. So the count of new asks on real work is
unknown.
