# Spike: can SlopCodeBench measure whether hone slows code decay?

**Date:** 2026-09-18 · **Status:** frozen. Written once, never maintained
against the code.

## Question

hone's lab is too easy on the *well structured* outcome. `seeded-structure`
passed nine times of nine, and hone has no mechanism aimed at that outcome.
SlopCodeBench measures structural decay over a long series of changes by one
agent. Can it measure hone? The paper says prompt-side work moves the
starting quality and not the rate of decay. Most of hone is prompt text, so
that finding hits us. A garden pass between changes and the
consolidate critic inside a change are mechanisms and not prompts, so they
are the part worth testing.

## What I did

Read the paper at `arxiv.org/html/2603.24755v2`, sections 2.3, 2.4, 3.1 to
3.4, and appendix C, from the HTML that arXiv serves. Cloned
`github.com/SprocketLab/slop-code-bench` and read the README, the docs, the
Claude Code adapter, the run configs, and the metric driver. Installed and
ran the metric tool `scb-check` on a small Python directory and on this
repository. Ran no benchmark problem and made no model call. Checked
`docker`, `python3`, and `uv` on this machine.

Every number below comes from the paper or from the clone, except where I
mark it unchecked.

## Finding

### The brief's numbers are the first version

The paper has two versions. v1 is 20 problems and 93 checkpoints. v2, posted
2026-05-07, is **36 problems and 196 checkpoints**, and I read v2. Problems
run 3 to 8 checkpoints. Three problems have 3: `dag_execution`,
`eve_jump_planner`, `eve_route_planner`.

### The code, the license, and the state of it

MIT, and the clone's last commit is 2026-08-04, so it is a month old and
alive. The problems themselves have moved out to a second repository,
`gabeorlanski/scb-problems`, and to a Harbor dataset. I did not clone that
one. `docs/KNOWN_ISSUES.md` says the configuration is hard to use and that a
few reference solutions fail their own tests, with the tests as ground
truth.

### The harness runs Claude Code, and it can load a plugin

The harness is its own CLI, `slop-code run`. Each checkpoint runs in a fresh
Docker container as a non-root user, and only the working directory survives
between checkpoints. The image installs `@anthropic-ai/claude-code` at a
pinned npm version and calls it headless:

```
claude --output-format stream-json --verbose --model <id> \
       --max-turns <n> --permission-mode bypassPermissions --print -- <task>
```

The agent config carries `extra_args`, which the adapter appends to that
command line. It also carries `settings`, which the adapter writes to a
`settings.json` and bind-mounts at the container's `~/.claude`. The
environment config carries `extra_mounts`. So `--plugin-dir` with hone mounted in is available in
principle. I did not run it, so treat "hone loads and its hooks fire inside
the container" as unchecked. I also did not check whether the image has
`git`, which hone needs for worktrees and commits.

Nothing in the harness runs a command between checkpoints. I grepped for a
pre- or post-checkpoint hook and found none. A garden arm needs a patch at
the one call site in `src/slop_code/entrypoints/problem_runner/`, which is a
second `claude --print "/hone:garden"` call after the checkpoint's own call.

The paper used Claude Code 2.0.51 for Opus 4.5, 2.1.32 for Opus 4.6, and
2.1.44 for Sonnet 4.6, each at thinking level high. This machine runs 2.1.277.
The paper's Claude rows are Opus 4.5, 4.6, 4.7 and Sonnet 4.6. There is no
Opus 5 row, so no published baseline exists for the model hone pins. The
clone does ship `configs/models/opus-5.yaml`.

### What a problem costs

Per checkpoint, from the paper's table 1, best run per model:

| Model | $/checkpoint | Minutes/checkpoint | Whole sweep |
| --- | --- | --- | --- |
| Opus 4.5 | 2.53 | 7.2 | 492 |
| Opus 4.6 | 3.17 | 13.1 | 621 |
| Opus 4.7 | 2.17 | 6.8 | 425 |
| Sonnet 4.6 | 1.96 | 14.2 | 384 |

So a 5-checkpoint problem is 11 to 16 dollars and under an hour of wall
clock. Each run has a two-hour limit per checkpoint and no cost cap. The
clone ships subsets for this reason: `configs/runs/lite.yaml` is five
problems, and `lite_under20.yaml` is `mvvault` and `xjq`, eleven checkpoints,
called a strict under-20-dollar subset.

### Both metrics are deterministic scripts, and they run on any directory

The two scores come from one pinned tool. The harness shells out to
`uvx scb-check==0.1.3 check --report --include-all <dir>` and reads its JSON.
So the metric is not tangled up in the benchmark.

- Erosion is the share of complexity mass held by functions over cyclomatic
  complexity 10. Mass of a function is its cyclomatic complexity times the
  square root of its source lines.
- Verbosity counts the lines that match one of 137 hand-written ast-grep
  rules, plus the lines that belong to a structural clone, over lines of
  code. A line that two rules hit counts once.

I ran it. On three Python files it took half a second and printed
`verbosity`, `erosion`, `cog_erosion`, the masses, and the counts. On this
repository it printed `no Python files found`. **It is Python only at 0.1.3.**
The lab's fixtures are TypeScript, so the tool cannot serve the lab as it
stands. Serving the lab means a Python fixture, or an equivalent of the two
formulas for TypeScript. The erosion half is easy anywhere a complexity tool
exists. The verbosity half is 137 Python rules and a clone detector, so it is
not.

### What the paper tested, and what it did not

Three prompts, all of them a system prompt inside the checkpoint's single
call. `just-solve` is the baseline used for every headline number.
`anti-slop` lists patterns to avoid. `plan-first` orders plan, simple
solution, edge cases, then "Refactor to ensure the code is high quality" as
step 4.

The result, on three GPT models. Erosion fell 34 to 58 percent and verbosity
27 to 36 percent at the start. The average slope did not move, at 1.3
percentage points per checkpoint. Strict correctness fell 2.4 points for
anti-slop and 3.6 for plan-first. Cost per checkpoint rose 12 percent.

**No arm had a separate cleanup step between checkpoints. No arm had a
second agent or a reviewer.** The closest thing is that one sentence inside
`plan-first`. So the paper's warning does not cover what hone does, and the
question is open.

The clone has one prompt the paper does not, `configs/prompts/plan-and-test.jinja`.
It orders a written plan file, then the test suite, then the simple solution,
then simplification. That is hone's loop written as a prompt. It is the right
control arm for telling hone's mechanism apart from hone's advice.

### Python only is half right

The paper says the problems are language-agnostic by construction, because
every checkpoint specifies only CLI or API behaviour. It then says all
experiments are Python, for cost. The metric tool is Python only today. So
the benchmark is Python in practice and not by design.

### This machine

`python3` 3.14.4 and `uv` 0.11.16 are here. **`docker` is not installed**,
and the harness needs it. There is a `local` environment type in the configs,
which would run the agent on the host with no container. That is the wrong
trade for an agent under `bypassPermissions`.

## The cheapest experiment that would answer the question

First, the target. Chasing the rate of decay is the wrong plan for hone, and
the arithmetic says so. Per-checkpoint spread is 0.20 for erosion and 0.18
for verbosity across agent checkpoints, and the mean rise is 0.026 per
checkpoint for erosion. A slope fitted over six checkpoints then carries a
standard error near 0.036. Detecting a halved slope at that spread needs
something like a hundred trajectories per arm. That is tens of thousands of
dollars, and it is out of reach.

The level at the last checkpoint is the honest target, and it is also the
thing a user cares about. A mechanism that runs every checkpoint can hold
the level flat while leaving the per-checkpoint rise untouched. The paper
would call that no change in the rate. A maintainer would call it the whole
point.

Five lines, then:

1. Two arms, paired by problem and by seed: bare Claude Code on opus, and
   bare plus one `/hone:garden` call between checkpoints. Drop the full hone
   loop for now.
2. Five problems of five or six checkpoints each, about 27 checkpoints per
   arm, one trajectory per problem per arm.
3. Compare erosion and verbosity at the last checkpoint, paired across the
   five problems, and report the correctness column beside it.
4. Cost: about 80 dollars for the bare arm, and about 140 for the garden arm
   at an assumed 2 dollars a call. Call it 250 dollars with one rerun, and a
   day of wall clock. Docker, a patched runner, and a mounted plugin come
   first.
5. Five paired problems detects a level gap of about 0.15 at the spread
   above. Anything smaller than that is not worth the money.

Why line 1 drops the full hone arm. hone needs `git`, a test adapter from
`/hone:setup`, a worktree, and gates that hand a judgment back to a person.
A headless call with nobody to answer can stop and report rather than land.
That reads as a failed checkpoint, and it leaves the workspace half
finished. The quality reading of a half-finished workspace measures nothing.
Making that arm fair is its own project, and it should wait until the garden
arm shows an effect worth chasing.

The honest verdict. The mechanism question is real, and the benchmark can
carry it. But the price is roughly 250 dollars plus several days of harness
work, and the payoff is one number about one outcome. Take the free half
now. `scb-check` is a pinned, deterministic, half-second script. A Python
fixture in the lab would give the *well structured* outcome its first real
measure at no model cost.

## Where it landed

No paid stage has run. [`roadmap.md`](../roadmap.md) carries the free
half as an open item: a Python fixture in the lab with `scb-check` as its
measure. The paid experiment is parked there with its price.
