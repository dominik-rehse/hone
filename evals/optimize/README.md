# The prose search

This directory searches for better wordings of hone's judgment prose. GEPA
runs a candidate wording on cases, lets a model read the failures, and lets
it rewrite one section. `HANDOFF.md` steps 6 and 8 own the program.

Four parts live here.

- `sections.py` splits a prompt file into named sections and joins it back.
  Its header has the rules. `test/optimize_test.sh` proves the round trip.
- `locks.json` says which sections the search may rewrite. A section is free
  only where cases aim at it. Everything else is locked.
- `adapter.py` is the GEPA adapter, the component selector, the rewrite
  prompt, and the guards. Its header says what each guard stops.
- `search.py` runs a search. `score.py` scores the versions it found.
- `cases/` holds cases the shipped prompt fails. Its README says why they
  are in no suite. `data/` rebuilds the private training data.

## Install once

The project runs with `uv` only. Never use `pip`. The environment lives
outside the repository, so nothing lands in git.

```bash
export UV_PROJECT_ENVIRONMENT=/var/tmp/hone-optimize/venv
export PYTHONDONTWRITEBYTECODE=1
uv sync --project evals/optimize
```

## Run a search

Print the estimate first. It is plan usage, not API money.

```bash
uv run --project evals/optimize evals/optimize/search.py \
    --data /var/tmp/hone-optimize/data/plan-critic \
    --adjudication /var/tmp/hone-optimize/adjudication/adjudication.json \
    --run-dir /var/tmp/hone-optimize/runs/2026-09-20-plan-critic \
    --budget 900 --dry-run
```

Drop `--dry-run` to run it. A search takes hours, so run it in the
background and read `<run-dir>/run_log.txt`.

## The usage limit

Several workers share one plan, so the limit hits during a long search and
holds for hours. The search handles that by itself. A call that comes back
empty is never scored. The adapter waits, writes one log line per wait, and
tries again. The wait grows to thirty minutes and then holds there, and
nothing gives up. So a search started in the background survives a limit
with no help.

## Stop and resume a search

To stop a running search cleanly, write a file named `gepa.stop` in the run
directory. The search finishes its iteration, saves, and exits. Wait for the
process to exit before you start another one.

The run directory holds the whole state. Run the same command again, and the
search goes on from its last checkpoint. The reply cache under
`/var/tmp/hone-optimize/reply-cache` survives too, so a repeated call is
free.

One search per run directory. `search.pid` holds the lock, and a second
search on the same directory refuses to start. Two searches on one directory
write the same state file and undo each other.

## Score the front

Each stage costs money, so run them one at a time. The reply cache makes a
repeat free.

```bash
for stage in validation holdout suite report; do
  uv run --project evals/optimize evals/optimize/score.py \
      --run-dir /var/tmp/hone-optimize/runs/2026-09-20-plan-critic \
      --data /var/tmp/hone-optimize/data/plan-critic \
      --adjudication /var/tmp/hone-optimize/adjudication/adjudication.json \
      --stage "$stage"
done
```

The `report` stage prints the table and runs the leak check. Run the
`holdout` stage once, at the end.

## The rules that hold

- Never read a held-out item or a held-out case, and never show one to the
  model that rewrites.
- The private data stays under `/var/tmp/`. No brief, and no name from a
  brief, enters this repository. `score.py --stage report` checks each
  candidate for that before you copy it in.
- The search never edits a shipped prompt. A version ships later, as an
  ordinary candidate through `evals/candidate.sh` and the release gate.
- To free a locked section, move its entry in `locks.json` and name the case
  that now aims at it.

`test/gepa_adapter_test.sh` proves the plumbing with no model call. It skips
when `gepa` is not installed and the network is off.
