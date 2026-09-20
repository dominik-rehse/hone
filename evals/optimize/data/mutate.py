# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Inject one named defect into a clean brief, so a bullet gets its cases.

Most bullets under *What to hunt* in `agents/plan-critic.md` have no case
that aims at them, and the ablation rule then says the bullet stays. A case
that aims at a bullet needs a brief that carries exactly that defect and
nothing else.

A model writes the mutation, and this script drives it. The model never
returns a whole brief. It returns one anchor string, its replacement, and a
sentence on what the defect is. The script checks the anchor occurs exactly
once and applies it. So "nothing else changed" holds by construction, and
the second look only has to judge whether the defect is real and material.

The harmless arm asks for a reword or a reorder that changes no fact. Its
label is APPROVE, so the set punishes a critic that rejects any edit.

The bullet text comes from `evals/optimize/sections.py --fine`. Nothing here
hard-codes a bullet.

Usage:
  mutate.py --sources DIR --out DIR --prompt agents/plan-critic.md
            [--bullet NAME]... [--per-bullet N] [--harmless N]
            [--model NAME] [--seed N] [--max-words N] [--jobs N]
"""

import argparse
import concurrent.futures
import json
import pathlib
import random
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
SECTIONS = HERE.parent / "sections.py"

ASK = """You are building test data for a code-review critic.

Below is (1) one rule the critic follows, and (2) a brief that the critic
approved. The brief is clean with respect to that rule.

Your job: edit the brief so that it breaks that one rule, and nothing else.

Rules for the edit.
- Change as little text as possible. One sentence, one bullet, or one added
  line.
- The defect must be real and material. A critic that follows the rule must
  have to reject the brief. Do not make a cosmetic change.
- Keep the brief plausible. It must still read as a Plan a person wrote.
- Break no other rule. Do not add a placeholder unless the rule is about
  placeholders. Do not leave the brief self-contradictory in a second way.

Return one JSON object and nothing else:

{{"anchor": "...", "replacement": "...", "defect": "..."}}

`anchor` is text copied EXACTLY from the brief, between one and six lines,
and it must occur exactly once in the brief. `replacement` is that text
after your edit. `defect` is one sentence saying what now breaks the rule.

THE RULE
{rule}

THE BRIEF
{brief}
"""

HARMLESS_ASK = """You are building test data for a code-review critic.

Below is a brief that the critic approved. Edit it so that the wording
changes and the facts do not. Reword one sentence, or reorder two adjacent
bullets of one list. Add no fact, drop no fact, change no number, no path,
and no file name. The edited brief must still deserve approval.

Return one JSON object and nothing else:

{{"anchor": "...", "replacement": "...", "defect": "..."}}

`anchor` is text copied EXACTLY from the brief, between one and six lines,
and it must occur exactly once in the brief. `replacement` is that text
after your edit. `defect` is one sentence saying what you changed.

THE BRIEF
{brief}
"""


def units(prompt_path):
    out = subprocess.run(
        [sys.executable, str(SECTIONS), "split", prompt_path, "--fine"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)


def bullet_texts(prompt_path):
    manifest = units(prompt_path)
    sections = manifest["sections"] if isinstance(manifest, dict) else manifest
    if isinstance(sections, dict):
        pairs = sections.items()
    else:
        pairs = [(s["name"], s["text"]) for s in sections]
    return {
        name: text
        for name, text in pairs
        if name.startswith("what-to-hunt/")
    }


def ask_model(prompt, model):
    proc = subprocess.run(
        ["claude", "-p", prompt, "--model", model, "--safe-mode",
         "--disallowedTools",
         "Read Grep Glob Bash Task Agent Edit Write NotebookEdit WebFetch WebSearch",
         "--output-format", "json"],
        capture_output=True, text=True,
    )
    try:
        env = json.loads(proc.stdout)
    except Exception:
        return None, 0.0
    if env.get("is_error", True):
        return None, env.get("total_cost_usd") or 0.0
    return env.get("result") or "", env.get("total_cost_usd") or 0.0


def parse(reply):
    if not reply:
        return None
    match = re.search(r"\{.*\}", reply, re.DOTALL)
    if not match:
        return None
    try:
        return json.loads(match.group(0))
    except Exception:
        return None


def one(job):
    brief = job["brief"]
    if job["bullet"] == "_harmless":
        prompt = HARMLESS_ASK.format(brief=brief)
    else:
        prompt = ASK.format(rule=job["rule"], brief=brief)
    reply, cost = ask_model(prompt, job["model"])
    job["cost"] = cost
    edit = parse(reply)
    if not edit or "anchor" not in edit or "replacement" not in edit:
        job["error"] = "no usable JSON from the model"
        return job
    anchor = edit["anchor"]
    if brief.count(anchor) != 1:
        job["error"] = f"anchor occurs {brief.count(anchor)} times"
        return job
    job["mutated"] = brief.replace(anchor, edit["replacement"])
    job["anchor"] = anchor
    job["replacement"] = edit["replacement"]
    job["defect"] = edit.get("defect", "")
    return job


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sources", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--prompt", default="agents/plan-critic.md")
    ap.add_argument("--bullet", action="append", default=[])
    ap.add_argument("--per-bullet", type=int, default=10)
    ap.add_argument("--harmless", type=int, default=12)
    ap.add_argument("--model", default="claude-sonnet-5")
    ap.add_argument("--seed", type=int, default=20260920)
    ap.add_argument("--max-words", type=int, default=1800)
    ap.add_argument("--jobs", type=int, default=6)
    args = ap.parse_args()

    sources = pathlib.Path(args.sources)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    pool = []
    for case in sorted(sources.iterdir()):
        brief_path = case / "brief.md"
        if not brief_path.is_file():
            continue
        text = brief_path.read_text(encoding="utf-8")
        if len(text.split()) > args.max_words:
            continue
        pool.append({"source": case.name, "brief": text})
    if not pool:
        sys.exit("no source briefs small enough")

    rules = bullet_texts(args.prompt)
    names = args.bullet or sorted(rules)
    rng = random.Random(args.seed)

    jobs = []
    for name in names:
        short = name.split("/")[-1]
        picks = rng.sample(pool, min(args.per_bullet, len(pool)))
        for n, src in enumerate(picks):
            jobs.append({"bullet": name, "short": short, "rule": rules[name],
                         "brief": src["brief"], "source": src["source"],
                         "model": args.model,
                         "name": f"{short}-{n:02d}"})
    for n, src in enumerate(rng.sample(pool, min(args.harmless, len(pool)))):
        jobs.append({"bullet": "_harmless", "short": "harmless", "rule": "",
                     "brief": src["brief"], "source": src["source"],
                     "model": args.model, "name": f"harmless-{n:02d}"})

    print(f"mutations to write: {len(jobs)} on {args.model}")
    print(f"estimate: about {len(jobs) * 0.05:.2f} dollars of plan usage")

    done = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool_x:
        for job in pool_x.map(one, jobs):
            done.append(job)

    index = []
    cost = 0.0
    failed = 0
    for job in done:
        cost += job.get("cost", 0.0)
        if "mutated" not in job:
            failed += 1
            continue
        case = out / job["name"]
        case.mkdir(parents=True, exist_ok=True)
        (case / "brief.md").write_text(job["mutated"], encoding="utf-8")
        label = "APPROVE" if job["bullet"] == "_harmless" else "REJECT"
        (case / "expected").write_text(label + "\n", encoding="utf-8")
        (case / "edit.json").write_text(
            json.dumps({"anchor": job["anchor"],
                        "replacement": job["replacement"],
                        "defect": job["defect"]}, indent=2) + "\n",
            encoding="utf-8")
        index.append({
            "id": job["name"], "label": label, "bullet": job["bullet"],
            "category": job["short"], "source_id": job["source"],
            "chain": "mut:" + job["source"], "origin": "generated",
            "defect": job["defect"], "label_strength": "by construction",
            "label_source": f"defect injected against the bullet {job['short']}",
            "words": len(job["mutated"].split()),
        })

    (out / "index.json").write_text(
        json.dumps({"items": index}, indent=2) + "\n", encoding="utf-8")
    print(f"written: {len(index)}, failed: {failed}, cost: {cost:.2f} dollars")
    per = {}
    for item in index:
        per[item["category"]] = per.get(item["category"], 0) + 1
    for name in sorted(per):
        print(f"  {name}: {per[name]}")


if __name__ == "__main__":
    main()
