"""Score the versions on a finished front, and the shipped prompt beside them.

Phase D of HANDOFF.md step 6. Four numbers per version:

  1. the full adjudicated validation part of the private set
  2. the held-out part, once, at the end
  3. hone's own suite at three votes, with and without the held-out cases
  4. the word count

Usage (from the repository root):

    UV_PROJECT_ENVIRONMENT=/var/tmp/hone-optimize/venv \\
    PYTHONDONTWRITEBYTECODE=1 \\
    uv run --project evals/optimize evals/optimize/score.py \\
        --run-dir /var/tmp/hone-optimize/runs/2026-09-20-plan-critic \\
        --data /var/tmp/hone-optimize/data/plan-critic \\
        --adjudication /var/tmp/hone-optimize/adjudication/adjudication.json \\
        --stage validation

`--stage` runs one stage at a time, because each one costs money and a usage
limit may stop it. The reply cache makes a repeat free. The stages are
`validation`, `holdout`, `suite`, and `report`.

NOBODY READS A HELD-OUT ITEM. The `holdout` stage scores them and prints
counts. It never prints a brief, an id, or a reply.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import pathlib
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import adapter as A  # noqa: E402
import search as S  # noqa: E402

REPO = S.REPO


def warm_from_seed(cache: A.ReplyCache, data_dir: str, model: str, digest: str) -> int:
    """Put the seed run's replies in the cache under the shipped digest.

    The seed of 2026-09-20 ran the shipped prompt over every train and
    validation field item at one vote. Those replies are exactly what the
    baseline needs, so the baseline pass costs nothing for them.
    """
    path = pathlib.Path(data_dir, "seed-opus-field.jsonl")
    if not path.exists():
        return 0
    warmed = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        if row.get("model") != model or not row.get("votes"):
            continue
        reply = row["votes"][0].get("reply") or ""
        if A.VERDICT.search(reply):
            cache.put(model, digest, row["case"], reply)
            warmed += 1
    return warmed


def score_set(task: A.PlanCriticAdapter, assembler, candidate, items) -> dict:
    batch = task.evaluate(list(items), candidate, capture_traces=False)
    counts = collections.Counter()
    for item, score in zip(items, batch.scores):
        counts[item.expected + "_total"] += 1
        counts[item.expected + "_right"] += int(score)
    right = sum(batch.scores)
    return {
        "n": len(items),
        "right": right,
        "accuracy": right / max(1, len(items)),
        "approve_right": counts["APPROVE_right"],
        "approve_total": counts["APPROVE_total"],
        "reject_right": counts["REJECT_right"],
        "reject_total": counts["REJECT_total"],
    }


def run_suite(prompt_file: str | None, holdout: bool, out_json: str) -> dict:
    """hone's own suite at three votes, through `evals/run.sh` itself."""
    # Two calls at a time, as everywhere else here. The plan's limit hits
    # during a long scoring pass, and `run.sh` scores a dead call as no
    # answer, which is a loud FAIL. `--cache` makes a repeat free, so a
    # second pass repairs what the limit broke.
    cmd = ["bash", os.path.join(REPO, "evals/run.sh"), "plan-critic",
           "--votes", "3", "--jobs", "2", "--json", out_json, "--cache"]
    if prompt_file:
        cmd += ["--prompt-file", prompt_file]
    if holdout:
        cmd.append("--holdout")
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO)
    tail = (proc.stdout or "").strip().splitlines()[-6:]
    cases = {}
    if os.path.exists(out_json):
        for line in open(out_json, encoding="utf-8"):
            row = json.loads(line)
            cases[row["case"]] = row["pass"]
    return {
        "passed": sum(1 for v in cases.values() if v),
        "total": len(cases),
        "failures": sorted(c for c, v in cases.items() if not v),
        "tail": tail,
        "returncode": proc.returncode,
    }


def versions(run_dir: pathlib.Path, assembler) -> dict[str, str]:
    """Every saved candidate that differs from the shipped prompt."""
    out = {}
    shipped = assembler.shipped_text
    for path in sorted((run_dir / "candidates").glob("cand-*.md")):
        text = path.read_text(encoding="utf-8")
        if text != shipped:
            out[path.stem] = str(path)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--adjudication", required=True)
    ap.add_argument("--target", default="plan-critic")
    ap.add_argument("--model", default="")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--stage", required=True,
                    choices=["validation", "holdout", "suite", "report"])
    ap.add_argument("--only", default="", help="comma-separated version names")
    args = ap.parse_args()

    run_dir = pathlib.Path(args.run_dir)
    prompt_path = os.path.join(REPO, "agents", f"{args.target}.md")
    model = args.model or S.frontmatter_model(prompt_path)
    free, _ = A.load_locks(os.path.join(REPO, "evals/optimize/locks.json"), args.target)
    assembler = A.PromptAssembler(prompt_path, free, str(run_dir / "prompts"))
    cache = A.ReplyCache("/var/tmp/hone-optimize/reply-cache")
    task = A.PlanCriticAdapter(assembler, REPO, model, cache, jobs=args.jobs)

    shipped_path = run_dir / "shipped.md"
    shipped_path.write_text(assembler.shipped_text, encoding="utf-8")
    _, shipped_digest, shipped_words = assembler.write(assembler.seed_candidate())
    warmed = warm_from_seed(cache, args.data, model, shipped_digest)
    print(f"warmed {warmed} seed replies into the cache for the shipped prompt")

    front = {"shipped": str(shipped_path)}
    front.update(versions(run_dir, assembler))
    if args.only:
        wanted = set(args.only.split(",")) | {"shipped"}
        front = {k: v for k, v in front.items() if k in wanted}
    print(f"versions to score: {', '.join(front)}")

    results_path = run_dir / "scores.json"
    results = json.loads(results_path.read_text()) if results_path.exists() else {}

    adjudication = {r["id"]: r["judgment"]
                    for r in json.load(open(args.adjudication))["items"]}

    if args.stage in ("validation", "holdout"):
        part = "validation" if args.stage == "validation" else "holdout"
        # The held-out part keeps its labels. Nobody adjudicated it, and
        # nobody read it.
        items = S.load_items(args.data, part, adjudication if part == "validation" else {})
        print(f"{part}: {len(items)} items, about "
              f"{len(items) * 0.25:.0f} dollars per version")
        for name, path in front.items():
            candidate = candidate_of(assembler, path)
            row = score_set(task, assembler, candidate, items)
            row["words"] = A.word_count(pathlib.Path(path).read_text(encoding="utf-8"))
            results.setdefault(name, {})[part] = row
            if part == "holdout":
                print(f"  {name:12} {row['right']:.0f}/{row['n']}  "
                      f"approve {row['approve_right']}/{row['approve_total']}  "
                      f"reject {row['reject_right']}/{row['reject_total']}")
            else:
                print(f"  {name:12} {row['right']:.0f}/{row['n']}  "
                      f"approve {row['approve_right']}/{row['approve_total']}  "
                      f"reject {row['reject_right']}/{row['reject_total']}  "
                      f"words {row['words']}")
            results_path.write_text(json.dumps(results, indent=1), encoding="utf-8")

    if args.stage == "suite":
        for name, path in front.items():
            for holdout in (False, True):
                key = "suite_holdout" if holdout else "suite"
                out = str(run_dir / f"suite-{name}{'-holdout' if holdout else ''}.jsonl")
                row = run_suite(None if name == "shipped" else path, holdout, out)
                results.setdefault(name, {})[key] = row
                print(f"  {name:12} {key:14} {row['passed']}/{row['total']}"
                      + (f"  failed: {', '.join(row['failures'])}" if row["failures"] else ""))
                results_path.write_text(json.dumps(results, indent=1), encoding="utf-8")

    if args.stage == "report":
        print()
        print("| version | words | val approve | val reject | holdout approve | "
              "holdout reject | suite | suite+holdout |")
        print("| --- | --- | --- | --- | --- | --- | --- | --- |")
        for name in front:
            row = results.get(name, {})
            val = row.get("validation", {})
            hold = row.get("holdout", {})
            suite = row.get("suite", {})
            suite_h = row.get("suite_holdout", {})
            print(f"| {name} | {val.get('words', '-')} "
                  f"| {frac(val, 'approve')} | {frac(val, 'reject')} "
                  f"| {frac(hold, 'approve')} | {frac(hold, 'reject')} "
                  f"| {suite.get('passed', '-')}/{suite.get('total', '-')} "
                  f"| {suite_h.get('passed', '-')}/{suite_h.get('total', '-')} |")
        print()
        for name, path in front.items():
            if name == "shipped":
                continue
            text = pathlib.Path(path).read_text(encoding="utf-8")
            leaked, shared = A.leak_report(text, [os.path.join(args.data, "set/cases")],
                                           assembler.shipped_text)
            print(f"leak check {name}: "
                  + ("no name from a brief" if not leaked else f"A NAME FROM A BRIEF: {leaked}"))
            print(f"  ordinary words it shares with a brief, read them: {shared}")

    print(f"\ncalls made: {task.calls_made}   cost: {task.cost_usd:.2f} dollars")
    return 0


def frac(row: dict, label: str) -> str:
    if not row:
        return "-"
    return f"{row.get(label + '_right', 0)}/{row.get(label + '_total', 0)}"


def candidate_of(assembler, path: str) -> dict:
    """Read a saved prompt file back as a candidate."""
    import sections
    return sections.to_candidate(sections.split_file(path, fine=True))


if __name__ == "__main__":
    raise SystemExit(main())
