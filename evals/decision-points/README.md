# Decision points: the middle-priced evaluator

The unit evals in [`../README.md`](../README.md) test hone's prose in a system
prompt. The lab in [`../lab/README.md`](../lab/README.md) runs the whole
plugin and costs dollars. This suite sits between them.

A case resumes a recorded `/hone:run` session just before a decision, and it
grades the next action. `claude plugin eval` does the resuming, through
`context.history_file`. One case run costs cents, and it takes seconds.

[`docs/spikes/2026-09-20-decision-point-cases.md`](../../docs/spikes/2026-09-20-decision-point-cases.md)
has the design, the discrimination table, and the limits.

## Run

```bash
bash evals/decision-points/run.sh --dry-run          # the conditions and the cost
bash evals/decision-points/run.sh                    # every case, 3 runs
bash evals/decision-points/run.sh --tag land         # one step of the loop
bash evals/decision-points/run.sh --case 'verify-*'  # one glob, no braces
bash evals/decision-points/run.sh --plugin /var/tmp/candidate --runs 1
```

The header of `run.sh` lists every flag. It prints one JSON line per case:
the case, whether every run passed, the cost, and the seconds. `--plugin`
points at the plugin under test, so a search over wordings gives it a copy
of the plugin with another `skills/run/SKILL.md`.

`run.sh` needs three things of this machine, and it says which one is
missing. A clean `HOME`, which it makes. A session token, which it reads
through `../session-token.sh` and never writes down. And `socat` beside
`bwrap`, which the runner's own shell sandbox needs. Where the machine has no
socat package, unpack one and set `HONE_DP_SOCAT_DIR`.

## What a case is

```
cases/<case>/
  case.yaml            written by lib/author.sh
  scaffold.sh          written by lib/author.sh
  history.tmpl.jsonl   written by lib/author.sh
  files/               written by lib/author.sh
  prompt.md            yours: the next user turn, usually `Continue.`
  graders/*.md         yours: what the next action must and must not be
```

The template is not a session log. It holds `@@HONE_SKILL_RUN@@` where the
skill's text was, and `@@HONE_WORKSPACE@@` and `@@HONE_PLUGIN@@` where the
paths were. `scaffold.sh` renders it at run time from the plugin under test.
That is what makes a candidate wording the text the resumed session obeys.
The header of `lib/history.py` says why, and the spike note has the proof.

## Add a case

1. Find the moment. `python3 lib/history.py show <session log> --kept` lists
   the rows that a case can cut at. A lab sandbox keeps its session log under
   `<sandbox>/home/.claude/projects/*-repo/*.jsonl`.
2. Pick the cut. `--upto N` keeps the rows `0` to `N-1`, so the decision is
   what row `N` did in the recording.
3. Add a line to `sources.tsv`, then run `bash lib/author.sh <case>`.
4. Write `prompt.md` and the graders. Prefer `tool_used`, `tool_order`,
   `file_exists`, and `regex` over `llm`. The loop commits with
   `git -C <path> commit`, so a pattern of `git commit` alone can miss it.
5. Prove that the case discriminates. Run it on the shipped plugin and on a
   plugin whose governing section is gone:

   ```bash
   python3 evals/optimize/sections.py drop skills/run/SKILL.md -s 6-land \
       -o /var/tmp/cand/skills/run/SKILL.md
   bash evals/decision-points/run.sh --plugin /var/tmp/cand --case <case>
   ```

   A case that both arms pass pins nothing, and it does not stay. This is the
   rule of `../README.md`, *A case must discriminate*.
6. Run `bash test/decision_points_test.sh`.

Two rules hold for every cut. It must lie before the review step, or after
the recorded review had finished, because no nested `claude -p` reaches the
API under the runner. And the last kept row must never be a tool call with no
answer, which `lib/history.py` enforces.

## Rebuild a case

The recordings live in lab sandboxes under `/var/tmp/hone-lab/`, which do not
survive a reboot. `sources.tsv` names the sandbox of every case. When one is
gone, run its scenario again, put the new sandbox in `sources.tsv`, and run
`bash lib/author.sh <case>`. A lab run of that scenario costs about 2 dollars.

`lib/fixtures/` holds the seeded tree of each scenario, built by
`lib/make-fixture.sh` from a sandbox's base commit. `lib/extras/` holds what
`git archive` cannot carry: a git hook, a second branch, another run's
worktree.
