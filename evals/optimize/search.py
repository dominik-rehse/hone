"""Run a GEPA search over one hone critic prompt.

Usage (always through `uv`, from the repository root):

    UV_PROJECT_ENVIRONMENT=/var/tmp/hone-optimize/venv \\
    PYTHONDONTWRITEBYTECODE=1 \\
    uv run --project evals/optimize evals/optimize/search.py \\
        --data /var/tmp/hone-optimize/data/plan-critic \\
        --adjudication /var/tmp/hone-optimize/adjudication/adjudication.json \\
        --run-dir /var/tmp/hone-optimize/runs/2026-09-20-plan-critic \\
        --budget 1200

The run directory carries the whole state. A stopped run resumes from it,
so the same command after a usage limit goes on where it stopped. Write a
file named `gepa.stop` in the run directory to stop a run cleanly.

WHAT THE ADJUDICATION DOES. Phase A of HANDOFF.md step 6 judged every train
and validation field item where the seed run of claude-opus-5 disagreed with
the label. This script reads that file and applies it: an item judged
`unclear` is dropped, an item judged `critic-right` has its label flipped,
and an item judged `label-right` keeps its label. A search against wrong
labels would loosen the critic, so this happens before any call.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import adapter as A  # noqa: E402

import gepa  # noqa: E402

REPO = str(pathlib.Path(__file__).resolve().parents[2])

# Measured on 2026-09-20. A field brief is long, and claude-opus-5 writes a
# long finding list before the verdict. A generated case and a suite case are
# shorter, and they still cost about 15 cents, because the reply is the
# expensive half.
COST_FIELD = 0.30
COST_OTHER = 0.15


def load_items(data_dir: str, part: str, adjudication: dict) -> list[A.Item]:
    """The private items of one part, with the adjudication applied."""
    root = pathlib.Path(data_dir)
    index = {i["id"]: i for i in json.load(open(root / "set/index.json"))["items"]}
    ids = [line.strip() for line in open(root / f"set/{part}.ids") if line.strip()]
    items = []
    for case_id in ids:
        meta = index[case_id]
        assert meta["part"] == part, f"{case_id} is not in {part}"
        label = meta["label"]
        judgment = adjudication.get(case_id)
        if judgment == "unclear":
            continue
        if judgment == "critic-right":
            label = "REJECT" if label == "APPROVE" else "APPROVE"
        items.append(
            A.Item(
                id=case_id,
                path=str(root / "set/cases" / case_id),
                expected=label,
                origin=meta["origin"],
                category=meta.get("category") or "",
            )
        )
    return items


def load_case_dir(directory: str, origin: str, skip_suffixes=("-holdout", "-watch")) -> list[A.Item]:
    """hone's own cases, in the layout `evals/run.sh` reads."""
    items = []
    for path in sorted(pathlib.Path(directory).iterdir()):
        if not (path / "brief.md").exists():
            continue
        if any(path.name.endswith(s) for s in skip_suffixes):
            continue
        expected = (path / "expected").read_text(encoding="utf-8").strip().splitlines()[0]
        items.append(A.Item(id=f"{origin}:{path.name}", path=str(path),
                            expected=expected, origin=origin, category=""))
    return items


def pick_validation(items: list[A.Item], free_categories: set[str], seed: int,
                    field_approve: int = 8, other_reject: int = 4,
                    harmless: int = 4) -> list[A.Item]:
    """A stratified subset of the validation part.

    A full validation pass runs for every accepted candidate, and it is the
    main cost of the search. So the subset keeps what the search can move
    and samples the rest:

      * every generated case aimed at a free section, because those are the
        sections the search may rewrite;
      * every field rejection, the hardest quarter of the whole set;
      * a sample of the field approvals, where the critic is weakest;
      * a sample of the generated cases of locked categories, so a rewrite
        of Calibration cannot buy approvals by losing rejections elsewhere;
      * a sample of the harmless edits, which punish a critic that rejects
        any change.
    """
    rng = random.Random(seed)
    keep, pool_field_approve, pool_other, pool_harmless = [], [], [], []
    for item in items:
        if item.origin == "generated" and item.category in free_categories:
            keep.append(item)
        elif item.origin == "field" and item.expected == "REJECT":
            keep.append(item)
        elif item.origin == "field":
            pool_field_approve.append(item)
        elif item.category == "harmless":
            pool_harmless.append(item)
        else:
            pool_other.append(item)
    for pool, count in ((pool_field_approve, field_approve),
                        (pool_other, other_reject),
                        (pool_harmless, harmless)):
        picked = sorted(pool, key=lambda i: i.id)
        rng.shuffle(picked)
        keep.extend(picked[:count])
    return sorted(keep, key=lambda i: i.id)


def estimate(items, per_pass: int, budget: int) -> str:
    field = sum(1 for i in items if i.origin == "field")
    mean = (field * COST_FIELD + (len(items) - field) * COST_OTHER) / max(1, len(items))
    return (f"about {budget * mean:.0f} dollars of plan usage: {budget} metric calls "
            f"at a mean of {mean:.2f} dollars. One validation pass is {per_pass} calls.")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True, help="the private data directory")
    ap.add_argument("--adjudication", required=True)
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--budget", type=int, default=1200)
    ap.add_argument("--target", default="plan-critic")
    ap.add_argument("--model", default="", help="default: the agent's frontmatter")
    ap.add_argument("--reflection-model", default="claude-opus-5")
    ap.add_argument("--minibatch", type=int, default=10)
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--seed", type=int, default=20260920)
    ap.add_argument("--val-size", type=int, default=0, help="0 keeps the stratified default")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    prompt_path = os.path.join(REPO, "agents", f"{args.target}.md")
    model = args.model or frontmatter_model(prompt_path)
    free, locked = A.load_locks(os.path.join(REPO, "evals/optimize/locks.json"), args.target)

    run_dir = pathlib.Path(args.run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    take_the_lock(run_dir)
    assembler = A.PromptAssembler(prompt_path, free, str(run_dir / "prompts"))

    adjudication = {}
    if os.path.exists(args.adjudication):
        adjudication = {r["id"]: r["judgment"]
                        for r in json.load(open(args.adjudication))["items"]}

    train = load_items(args.data, "train", adjudication)
    train += load_case_dir(os.path.join(REPO, "evals/optimize/cases", args.target), "optimize-case")

    validation_all = load_items(args.data, "validation", adjudication)
    free_categories = {n.split("/")[-1] for n in free}
    validation = pick_validation(validation_all, free_categories, args.seed)
    if args.val_size:
        validation = validation[: args.val_size]
    validation += load_case_dir(os.path.join(REPO, "evals", args.target), "hone-case")

    print(f"target: {args.target}   model: {model}   rewriting model: {args.reflection_model}")
    print(f"free sections ({len(free)}): " + ", ".join(free))
    print(f"locked sections: {len(locked)}")
    print(f"train: {len(train)} items   validation: {len(validation)} items")
    print(f"adjudication: {len(adjudication)} judgments applied")
    print("estimate: " + estimate(validation, len(validation), args.budget))
    print(f"run dir: {run_dir}")
    if args.dry_run:
        for item in validation:
            print(f"  val {item.id:28} {item.expected:8} {item.origin:14} {item.category}")
        return 0

    cache = A.ReplyCache("/var/tmp/hone-optimize/reply-cache")
    task = A.PlanCriticAdapter(assembler, REPO, model, cache, jobs=args.jobs)
    reflection = A.ClaudeReflection(args.reflection_model, assembler.shipped_text)

    result = gepa.optimize(
        seed_candidate=assembler.seed_candidate(),
        trainset=train,
        valset=validation,
        adapter=task,
        reflection_lm=reflection,
        reflection_prompt_template=A.REFLECTION_TEMPLATE,
        module_selector=A.FreeOnlyRoundRobin(free),
        frontier_type="objective",
        reflection_minibatch_size=args.minibatch,
        cache_evaluation=True,
        max_metric_calls=args.budget,
        run_dir=str(run_dir),
        seed=args.seed,
        raise_on_exception=False,
        display_progress_bar=False,
    )

    print(f"\ncalls made: {task.calls_made}   cost: {task.cost_usd:.2f} dollars")
    print(f"rewrites proposed: {reflection.calls}   thrown away: {reflection.rejected}")
    summary = {
        "candidates": len(result.candidates),
        "best_idx": result.best_idx,
        "val_ids": [i.id for i in validation],
        "val_aggregate_scores": result.val_aggregate_scores,
        "val_aggregate_subscores": result.val_aggregate_subscores,
        "per_objective_best_candidates": {
            k: sorted(v) for k, v in (result.per_objective_best_candidates or {}).items()
        },
        "objective_pareto_front": result.objective_pareto_front,
        "parents": result.parents,
        "calls_made": task.calls_made,
        "task_cost_usd": task.cost_usd,
        "rewrites": reflection.calls,
        "rewrites_rejected": reflection.rejected,
    }
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")

    # Every candidate as a full prompt file, so a person can diff it against
    # the shipped one and `evals/run.sh --prompt-file` can score it.
    out = run_dir / "candidates"
    out.mkdir(exist_ok=True)
    for idx, candidate in enumerate(result.candidates):
        text = assembler.assemble(candidate)
        (out / f"cand-{idx:03d}.md").write_text(text, encoding="utf-8")
    print(f"summary: {run_dir / 'summary.json'}   candidates: {out}")
    return 0


def take_the_lock(run_dir: pathlib.Path) -> None:
    """One search per run directory, and no second one.

    Two searches on one run directory write the same state file and undo
    each other. That happened on 2026-09-20, because `gepa.stop` lets a run
    finish its iteration and a restart looked immediate. A stale lock from a
    dead process is taken over.
    """
    lock = run_dir / "search.pid"
    if lock.exists():
        try:
            other = int(lock.read_text().strip())
        except ValueError:
            other = 0
        if other and pathlib.Path(f"/proc/{other}").exists():
            raise SystemExit(
                f"another search holds {run_dir} as pid {other}. Stop it first: "
                f"write {run_dir / 'gepa.stop'} and wait for the process to exit."
            )
    lock.write_text(str(os.getpid()), encoding="utf-8")


def frontmatter_model(path: str) -> str:
    inside = False
    for line in open(path, encoding="utf-8"):
        if line.strip() == "---":
            if inside:
                break
            inside = True
            continue
        if inside and line.startswith("model:"):
            return line.split(":", 1)[1].strip()
    raise SystemExit(f"no model in the frontmatter of {path}")


if __name__ == "__main__":
    raise SystemExit(main())
