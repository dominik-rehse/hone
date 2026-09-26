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

## Replay of real commands

The replay reads 705 real commands (the 639 of
[the note before](2026-09-26-bash-guard-holes-replay.md) and newer ones)
and runs each through 0.64.0 and the new hook, from the directory it ran
in. The main session ran it on the first version of the reach, and a
later session ran it again on the same saved commands after the fix.

The first version of the reach added 20 asks and removed 3. One new ask
was right: a copy into `hooks/`. Seventeen were a loop over the
maintainer's repositories after a push, as in `for r in a b; do (cd
~/repos/$r && ...); done`. The walk knew each value of `r`, but the
reach's `cd` read a variable only when the whole word was `"$r"`. The
other two were a `cd ..` in a plain chain, which the walk refused, and a
lease test that cds into a directory its own `mkdir` and `git clone`
make.

After the fix, over 705 commands:

- 556 pass on both hooks, 131 ask on both, 12 are denied on both.
- 4 asks became passes, all right: three copies that only read a settings
  file, and a package install in a scratch directory the command makes.
- 2 passes became asks. The copy into `hooks/` is right. The lease test
  asks because its scratch directory has been deleted since, so its first
  `cd` goes nowhere the hook can place. With the directory in place it
  passes.
