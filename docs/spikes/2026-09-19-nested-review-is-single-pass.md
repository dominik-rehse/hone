# Spike: the nested `/code-review` is one pass, not a fan-out

**Date:** 2026-09-19 · **Status:** frozen. Written once, never maintained
against the code.

## Question

The roadmap said the nested review may not fan out: `subagent_stats.spawned`
read 0 in almost every envelope. The skill called the review multi-agent and
the loop's dearest step. Which of the two is wrong?

## What I did

Read 156 valid envelopes under `/var/tmp/hone-lab/2026091*/`, and the session
log each one names: `<sandbox>/home/.claude/projects/<cwd>/<session-id>.jsonl`,
with a `subagents/` directory beside it. Then ran the skill's command by hand
in a kept sandbox, on claude 2.1.278.

## Finding

The review does not fan out. The envelope was telling the truth. Every one of
the 156 sessions ran its review inside exactly one `general-purpose` subagent.
Across all of them there is one `Agent` call and no `Task` call. Each
subagent's own prompt names its recipe:

> `minimal prompt → single careful diff pass → ≤15 findings`

`num_turns` and `subagent_stats` read 0 because the command does not count the
subagent it reviews in.

The recipe key is the review model, not the level. On `claude-opus-5` the
`high` level selects that single-pass cell. Six lab runs used `--review-model`
for sonnet or haiku, and those six are exactly the ones that got an
angles-and-verify recipe.

Three runs by hand, on the same diff of 25 lines:

| command | agents | cost |
|---|---|---|
| the skill's, as written | 1 | $0.16 |
| the same, wide `--allowedTools` | 1 | $0.07 |
| `/code-review max` | 17 | **$16.03** |

So the allowlist is not what suppresses the fan-out. And `max` is no option: a
hundred times `high` on the smallest diff in the set. Cap a review run by hand
with `--max-budget-usd`.

Two denial patterns, and neither is about `git`. Of 446 denied commands, 27
open with `git`. 26 of those chain a half that runs code, such as `node
--test`. A probe passed `git -C <path>`, `git a && git b`, a pipe to `head`,
and `cd <worktree> && git status`. Only the executing half draws the refusal.
The 54 `cd` denials track where the loop started the call. 47 of them come from
the 22 runs that began in the repo root or the `mktemp -d` directory. The 134
that began inside the worktree hold the other 7.

What the denials cost is the review's own verification. 116 of the 156 reviews
spend words on what they could not check. 69 of those name the test suite, and
they mark findings plausible rather than confirmed.

A review costs $0.29 on average and $0.21 at the median, in a range of $0.09 to
$0.93. That is 12 percent of a run's total, so it is not the dearest step.

The catch rate still has zero counted runs. All 18 runs on disk that carry
`review_named` also carry `brief_named: yes`. In all nine `defect-in-hunk` runs
the builder fixed the defect before the review saw it.

## Where it landed

The run skill now says what the review is on the pinned model, and it
starts the review inside the worktree. The allowlist stays as it is.
[`review-bench-first-run`](2026-09-19-review-bench-first-run.md) measured
the catch rate that this note found unmeasured.
