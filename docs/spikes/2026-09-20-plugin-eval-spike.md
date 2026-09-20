# Spike: can `claude plugin eval` run hone?

**Date:** 2026-09-20 · **Status:** frozen. Written once, never maintained
against the code.

## Question

Step 1 of `HANDOFF.md`. `claude plugin eval` is Anthropic's eval runner for
plugins. Step 7 wants decision-point cases on it. Seven questions decide
whether hone can run under it at all.

## What I did

Wrote throwaway cases in `evals-spike/` and ran them one at a time on claude
2.1.278:

```
claude plugin eval . --eval-dir evals-spike --case <case> --runs 1 \
  --ablation none --model claude-opus-5 --trust-plugin --scaffold \
  --allow-tools Bash Write Edit --no-publish --keep-temp --json <out>.json
```

Six cases. Three are the ones step 1 names: `happy-path` and `plan-fork` from
the lab, and one `plan-critic` unit case through the `Agent` tool. Each lab
case scaffolds the lab's own fixture, and then runs the scenario's `seed.sh`.
Three more cases came out of the answers: `guard-denies` writes production
code in the primary tree, `history-resume` continues the `plan-fork` session,
and `sandbox-probe` reads the shell sandbox from inside.

Three things had to be cleared first, and each cost a refused run:

- The runner refuses a plugin with more than 20,000 entries. This repository
  holds about 40,000, because `evals/lab/out/` still holds 503 MB of runs
  from 2026-09-17. So the runs used a copy of the shipped directories under
  `/var/tmp/hone-spike/plugin`.
- A Bash grant refuses when `~/.docker` holds a symbolic link. Docker Desktop
  on WSL2 puts two there. `DOCKER_CONFIG` does not move the check, so the
  runs used a clean `HOME` and passed the session token in
  `CLAUDE_CODE_OAUTH_TOKEN`, as `evals/session-token.sh` does.
- The Bash sandbox needs `bwrap` and `socat`. This machine had no `socat`
  package, so the spike unpacked the `.deb` under `/var/tmp/hone-spike/opt`.

## Finding

**1. Do hone's hooks fire in a run? Yes, every kind.** The `SessionStart`
hook is the first pair of events in each trace, and it injects the workflow
rule. The kept session log of the `plan-fork` run carries a
`stop_hook_summary` with both `Stop` hooks. The gate took 32 ms and the nag
took 84 ms, and the nag's advisory text is there. A `PreToolUse` hook leaves no event of
its own, so `guard-denies` tested it by asking for a write of
`src/text/capitalize.js` in the primary tree. The trace holds the denial:
`hone guard: src/text/capitalize.js is a protected path in the primary tree`.

**2. Does the nested `/code-review` finish? No, and no flag opens it.** The
`happy-path` run built, verified, and consolidated, and then stopped at
review. Its report says the nested call answered `Not logged in · Please run
/login` with zero API time. The shell sandbox withholds the parent's
credentials, and the throwaway home holds none. It is worse than a missing
token. `sandbox-probe` ran `curl` against `api.anthropic.com` from inside the
sandbox, and got exit 7 with no HTTP code. A second run with
`--allow-tools "WebFetch(domain:api.anthropic.com)"` got exit 7 again. So no
nested `claude -p` call can reach the API. `EVAL_*` variables do reach the
shell, which is the one part of a workaround that works.

**3. Does a full `/hone:run` end inside the limit of 3,600 seconds? Yes for
the part that ran.** The `happy-path` case set `timeout_seconds: 3600` and
`max_turns: 200`. It reached the review step in 274 seconds and 41 turns, and
it stopped there for the reason above. A landing run of the same scenario
takes 4 to 10 minutes in the lab, which fits the cap. No run under the eval
runner has landed, so the whole loop is unmeasured.

**4. Does `context.history_file` resume a recorded session with the hooks on?
Yes.** `history-resume` named the kept session log of the `plan-fork` run as
its `history_file`, and its scaffold copied that run's workspace back in. The
next user turn asked which of the two builds the earlier session had picked.
The answer named the choice and the Plan file, and it read no file. All three
graders passed, and one of them matched the workflow rule in the trace, so
the hooks were on. The run took 7 seconds and cost 6 cents.

**5. Does the JSON carry the cost of each run and the verdict of each grader?
Yes.** Each run object holds `costUsd`, `judgeCostUsd`, `durationSeconds`,
`turns`, `error`, `score`, and `tracePath`. Each grader in it holds `name`,
`passed`, and an `explanation`. An `llm` grader reports its votes, such as
`judge votes: FAIL FAIL FAIL`. The per-run `costUsd` is a list-price estimate.

**6. Does `--keep-temp` keep the workspace? Yes, behind one `chmod`.** Each
run printed its kept directory, such as `/tmp/claude-eval-t1kvKJ`. The
workspace is at `sealed/home/cwd`, the trace at `out/trace.jsonl`, and the
session log under `config/projects/`. The kept tree is read-only and the
`sealed` directory is mode 000, so a grader needs `chmod 700` on both first.
The runner also warns against running git anywhere inside it. The lab's
`check.sh` files run git, so they would have to grade a copy.

**7. Does the `path` of a `file_exists` grader take a glob? Yes.** The
`plan-fork` case passed with `path: .plans/**/*.md`, and the explanation
echoed the glob. Two limits bit in the same suite. A file that the scaffold
made is invisible, because only files created during the run count. And
`src/text/*.js` failed in `happy-path`, because the loop writes that file
inside `.worktrees/text/slugify/`. A glob for a loop artifact has to carry
the worktree path.

Two things beside the seven. A regex on the trace does see a shell command.
The `plan-fork` session committed its Plan with `git -C <path> commit`. A
pattern of `git commit` missed that, and the grader passed for the wrong
reason. The seven answers cost $3.70 in plan usage over eight runs, and
`happy-path` was $1.90 of it.

## Where it landed

Step 7 of `HANDOFF.md` can go ahead. A decision-point case resumes a recorded
session with the hooks on, and it costs cents. Step 7 may not use a recorded
session that continues into the review step, because that step cannot run
here. Nothing else in this note has a home yet: `evals-spike/` is deleted,
and the lab stays where it is.
