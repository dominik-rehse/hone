"""A GEPA adapter over one hone critic prompt.

GEPA searches text. A candidate here is a dict from a section name of
`agents/<critic>.md` to that section's text, as `sections.py --fine` splits
it. `evaluate` puts the assembled file in the system slot and scores the
critic's verdict on each case. `make_reflective_dataset` hands the failures
to the model that rewrites one section.

THREE RULES HOLD THE SEARCH HONEST.

  * The lock. `locks.json` says which sections are free. A section is free
    only where cases aim at it. The component selector offers GEPA nothing
    else, and `_assemble` asserts the locked text again before every call.
    So a lock cannot fail open.
  * No case content in the prompt. A rewrite that copies a name or a value
    out of a brief writes the cases into the prompt. `_leaked_tokens` finds
    such a token in the proposal and throws the proposal away.
  * An infrastructure error is never a score of 0. A usage limit, an empty
    reply, or a dead call would look like a wrong verdict and steer the
    whole search. `_run_batch` retries such a case with a growing sleep.

THE CALL IS `evals/optimize/data/measure.sh`, unchanged. That script already
repeats `evals/run.sh`'s call shape: the prose in the system slot, the same
closing instruction, an empty working directory, `--safe-mode`, and every
tool denied. This module adds a reply cache around it, keyed on the model,
the system prompt, and the brief. GEPA's own `cache_evaluation` covers the
validation pass only, and the minibatches are most of the spend.

`words` is the third objective. It is one value per candidate, scaled
against the shipped prompt, and mapped so that higher is better:

    words_score = 1 - candidate_words / (2 * shipped_words)

The shipped prompt scores 0.5. A prompt half as long scores 0.75.
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, Iterable, List, Mapping, Sequence

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sections  # noqa: E402

from gepa.core.adapter import EvaluationBatch  # noqa: E402

VERDICT = re.compile(r"\b(APPROVE|REJECT)\b")
TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_./-]{3,}")
PART = re.compile(r"[./\-_]+")


def tokens(text: str) -> set:
    """Every word of four letters or more, and every part of a dotted path.

    A leak may arrive as `src/widgets/cache.py` or as the bare word `cache`,
    so the set holds both the whole token and its parts.
    """
    found = set()
    for word in TOKEN.findall(text):
        word = word.strip("._-/").lower()
        if len(word) < 4:
            continue
        found.add(word)
        for part in PART.split(word):
            if len(part) >= 4:
                found.add(part)
    return found


def names(text: str) -> set:
    """The tokens that read as a name or a value, not as English.

    A path, a dotted or underscored identifier, anything with a digit in
    it, a CamelCase word, and an all-caps word. An ordinary English word is
    not here, because a brief and a review prompt share their vocabulary
    and a rule on plain words would fire on every proposal.
    """
    found = set()
    for word in TOKEN.findall(text):
        core = word.strip("._-/")
        if len(core) < 4:
            continue
        looks_like_a_name = (
            any(ch.isdigit() for ch in core)
            or any(ch in "./_" for ch in core)
            or core.isupper()
            or core[1:] != core[1:].lower()      # an internal capital
        )
        if looks_like_a_name:
            found.add(core.lower())
            for part in PART.split(core.lower()):
                if len(part) >= 4:
                    found.add(part)
    return found


def strip_section(rendered: str) -> str:
    """The reflection prompt with the section under rewrite cut out.

    What is left is the case material. The section's own words are not a
    leak, so they must not count as one. The caller cuts the second copy,
    the one the reflective dataset carries per record.
    """
    i = rendered.find(SECTION_BEGIN)
    j = rendered.find(SECTION_END)
    if i < 0 or j < 0:
        return rendered
    return rendered[:i] + rendered[j + len(SECTION_END):]


def copied_phrase(proposal: str, cases: str, original: str, length: int = 8) -> str:
    """A run of words the proposal took verbatim from a case, or "".

    A leak does not have to carry a name. A sentence lifted from a brief is
    a leak too, and it reads as fluent prose.

    A run that the section already had is never a leak, however often the
    reflection prompt repeats the section. That is why `original` is here:
    the reflective dataset carries the section once per record, and the
    comparison runs on whitespace-normalized text, so a re-wrapped copy
    cannot slip past.
    """
    def norm(text: str) -> str:
        return " " + " ".join(text.lower().split()) + " "

    kept = norm(original)
    haystack = norm(cases).replace(kept.strip(), " ")
    words = norm(proposal).split()
    for start in range(0, max(0, len(words) - length + 1)):
        run = " ".join(words[start: start + length])
        if f" {run} " in kept:
            continue
        if f" {run} " in haystack:
            return run
    return ""

# A rewrite may not empty a section. It may shorten one to this share of the
# shipped section's words, and no further.
MIN_WORD_SHARE = 0.35
MIN_WORDS = 12

# How long to wait between retries of a call that gave no answer. The list
# runs out, and the last value then repeats for ever. Nothing here gives up:
# the plan's usage limit is shared with other workers, it hits during a long
# search, and it resets on its own.
BACKOFF = [30, 60, 120, 300, 600, 900, 1800]


def backoff(round_number: int) -> int:
    """The wait before the next try. It grows, then it holds at 30 minutes."""
    return BACKOFF[min(round_number, len(BACKOFF) - 1)]


@dataclass
class Item:
    """One case: a brief, its expected verdict, and where it came from."""

    id: str
    path: str          # the directory that holds brief.md and expected
    expected: str      # APPROVE or REJECT
    origin: str        # field, generated, hone-case, or optimize-case
    category: str      # the injected defect, where there is one


def load_locks(path: str, target: str) -> tuple[List[str], Dict[str, str]]:
    """Return the free section names, and the reason per locked section."""
    data = json.load(open(path, encoding="utf-8"))[target]
    return list(data["free"]), dict(data["locked"])


def word_count(text: str) -> int:
    return len(text.split())


class LockedSectionError(RuntimeError):
    """A candidate changed a section the search may not touch."""


class PromptAssembler:
    """Turns a candidate back into a prompt file, and holds the lock."""

    def __init__(self, prompt_path: str, free: Sequence[str], out_dir: str):
        self.prompt_path = prompt_path
        self.base = sections.split_file(prompt_path, fine=True)
        self.free = list(free)
        self.baseline = sections.to_candidate(self.base)
        unknown = [n for n in self.free if n not in self.baseline]
        if unknown:
            raise KeyError(f"free section not in {prompt_path}: {unknown}")
        self.shipped_text = sections.join_sections(self.base)
        self.shipped_words = word_count(self.shipped_text)
        self.out_dir = pathlib.Path(out_dir)
        self.out_dir.mkdir(parents=True, exist_ok=True)

    def seed_candidate(self) -> Dict[str, str]:
        return dict(self.baseline)

    def check(self, candidate: Mapping[str, str]) -> None:
        """Assert the lock and the minimum length. Raise on a breach."""
        for name, text in candidate.items():
            if name in self.free:
                original = self.baseline[name]
                if not text.strip():
                    raise LockedSectionError(f"section emptied: {name}")
                floor = max(MIN_WORDS, int(MIN_WORD_SHARE * word_count(original)))
                if word_count(text) < floor:
                    raise LockedSectionError(
                        f"section under the floor of {floor} words: {name}"
                    )
            elif text != self.baseline.get(name):
                raise LockedSectionError(f"locked section changed: {name}")

    def normalize(self, candidate: Mapping[str, str]) -> Dict[str, str]:
        """Give each rewritten section the original's trailing whitespace.

        A section's text ends with the newlines that separate it from the
        next one. The rewriting model returns prose, and it drops them. The
        joined file then glues the next bullet or the next heading onto the
        last sentence, and a glued `## Output` stops being a heading. So the
        tail is restored here, before anything reads the file.
        """
        out: Dict[str, str] = {}
        for name, text in candidate.items():
            original = self.baseline.get(name, "")
            if name in self.free and original:
                tail = original[len(original.rstrip()):] or "\n"
                out[name] = text.rstrip() + tail
            else:
                out[name] = text
        return out

    def assemble(self, candidate: Mapping[str, str]) -> str:
        candidate = self.normalize(candidate)
        self.check(candidate)
        return sections.join_sections(
            sections.from_candidate(self.base, dict(candidate))
        )

    def write(self, candidate: Mapping[str, str]) -> tuple[str, str, int]:
        """Write the assembled prompt. Returns its path, digest, and words."""
        text = self.assemble(candidate)
        digest = hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]
        path = self.out_dir / f"{digest}.md"
        if not path.exists():
            path.write_text(text, encoding="utf-8")
        return str(path), digest, word_count(text)


class ReplyCache:
    """A reply per (model, prompt digest, case). Survives a resumed run."""

    def __init__(self, root: str):
        self.root = pathlib.Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, model: str, digest: str, case_id: str) -> pathlib.Path:
        key = hashlib.sha256(f"{model}\x00{digest}\x00{case_id}".encode()).hexdigest()
        return self.root / key[:2] / f"{key}.json"

    def get(self, model: str, digest: str, case_id: str) -> str | None:
        path = self._path(model, digest, case_id)
        if not path.exists():
            return None
        try:
            return json.loads(path.read_text(encoding="utf-8"))["reply"]
        except Exception:
            return None

    def put(self, model: str, digest: str, case_id: str, reply: str) -> None:
        path = self._path(model, digest, case_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"reply": reply}), encoding="utf-8")


class PlanCriticAdapter:
    """The GEPA adapter. `DataInst` is an `Item`."""

    propose_new_texts = None

    def __init__(
        self,
        assembler: PromptAssembler,
        repo_root: str,
        model: str,
        cache: ReplyCache,
        # Two calls at a time, and no more. The plan's usage limit hits in
        # the middle of a search, and a wide fan-out then throws away
        # everything in flight. Two keeps that loss small.
        jobs: int = 2,
        log: Callable[[str], None] = print,
        runner: Callable[..., Dict[str, str]] | None = None,
        sleeper: Callable[[float], None] = time.sleep,
    ):
        self.assembler = assembler
        self.repo_root = repo_root
        self.model = model
        self.cache = cache
        self.jobs = jobs
        self.log = log
        self._runner = runner or self._measure
        self._sleep = sleeper
        self.calls_made = 0
        self.cost_usd = 0.0

    # ---------------------------------------------------------------- calls

    def _measure(self, prompt_file: str, items: Sequence[Item]) -> Dict[str, str]:
        """One `measure.sh` run over a set of cases. Returns id -> reply."""
        tmp = tempfile.mkdtemp(prefix="hone-gepa-")
        try:
            cases = pathlib.Path(tmp, "cases")
            cases.mkdir()
            for item in items:
                dest = cases / item.id
                dest.mkdir()
                shutil.copy(pathlib.Path(item.path, "brief.md"), dest / "brief.md")
                (dest / "expected").write_text(item.expected + "\n", encoding="utf-8")
            out = pathlib.Path(tmp, "out.jsonl")
            cmd = [
                "bash",
                os.path.join(self.repo_root, "evals/optimize/data/measure.sh"),
                "--cases-dir", str(cases),
                "--out", str(out),
                "--model", self.model,
                "--prompt-file", prompt_file,
                "--jobs", str(self.jobs),
            ]
            proc = subprocess.run(cmd, capture_output=True, text=True)
            replies: Dict[str, str] = {}
            if out.exists():
                for line in out.read_text(encoding="utf-8").splitlines():
                    row = json.loads(line)
                    reply = row["votes"][0]["reply"] if row.get("votes") else ""
                    self.cost_usd += sum(v.get("cost_usd") or 0.0 for v in row.get("votes", []))
                    replies[row["case"]] = reply
            if not replies and proc.returncode != 0:
                self.log(f"measure.sh failed: {proc.stderr[-400:]}")
            return replies
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def _run_batch(self, prompt_file: str, digest: str, items: Sequence[Item]) -> Dict[str, str]:
        """Every case answered, with the cache in front and retries behind.

        A case with no verdict is never scored. It is retried, because an
        empty reply is a usage limit or a dead call far more often than a
        model that declined to answer. A case is given up only when other
        cases in the same round did answer, which tells us the harness is
        alive and the fault is that one case.

        THE WAIT HAS NO CAP. Several workers share one plan, so the limit
        hits during a long search and holds for hours. A search that gave up
        would need a person. So the batch waits, logs one line per wait, and
        goes on when the limit resets.
        """
        replies: Dict[str, str] = {}
        todo: List[Item] = []
        for item in items:
            hit = self.cache.get(self.model, digest, item.id)
            if hit is not None and VERDICT.search(hit):
                replies[item.id] = hit
            else:
                todo.append(item)

        rounds = 0
        alive = False
        tries: Dict[str, int] = {}
        while todo:
            fresh = self._runner(prompt_file, todo)
            self.calls_made += len(todo)
            for item in todo:
                tries[item.id] = tries.get(item.id, 0) + 1
                reply = fresh.get(item.id, "")
                if VERDICT.search(reply):
                    self.cache.put(self.model, digest, item.id, reply)
                    replies[item.id] = reply
                    alive = True
            todo = [i for i in todo if i.id not in replies]
            if not todo:
                break
            if alive and all(tries[i.id] >= 3 for i in todo):
                # Some case in this batch answered, so the harness is up and
                # the model is reachable. What is left will not answer, and
                # three tries is enough. The trace records the silence.
                for item in todo:
                    replies[item.id] = ""
                break
            wait = backoff(rounds)
            self.log(
                f"no answer on {len(todo)} of {len(items)} case(s) in round "
                f"{rounds + 1}. This looks like the plan's usage limit. "
                f"Waiting {wait}s, then trying again. The search does not give up."
            )
            self._sleep(wait)
            rounds += 1
        return replies

    # ------------------------------------------------------------ interface

    def evaluate(
        self,
        batch: List[Item],
        candidate: Dict[str, str],
        capture_traces: bool = False,
    ) -> EvaluationBatch:
        prompt_file, digest, words = self.assembler.write(candidate)
        before = self.calls_made
        replies = self._run_batch(prompt_file, digest, batch)
        words_score = max(0.0, 1.0 - words / (2.0 * self.assembler.shipped_words))

        outputs, scores, objectives, traces = [], [], [], []
        for item in batch:
            reply = replies.get(item.id, "")
            found = VERDICT.findall(reply.upper())
            token = found[-1] if found else ""
            right = 1.0 if token == item.expected else 0.0
            outputs.append({"id": item.id, "verdict": token})
            scores.append(right)
            objective = {"words": words_score}
            if item.expected == "REJECT":
                objective["reject_right"] = right
            else:
                objective["approve_right"] = right
            objectives.append(objective)
            if capture_traces:
                traces.append(
                    {
                        "id": item.id,
                        "brief": pathlib.Path(item.path, "brief.md").read_text(encoding="utf-8"),
                        "expected": item.expected,
                        "category": item.category,
                        "origin": item.origin,
                        "verdict": token,
                        "reply": reply,
                        "score": right,
                    }
                )
        return EvaluationBatch(
            outputs=outputs,
            scores=scores,
            trajectories=traces if capture_traces else None,
            objective_scores=objectives,
            num_metric_calls=self.calls_made - before,
        )

    def make_reflective_dataset(
        self,
        candidate: Dict[str, str],
        eval_batch: EvaluationBatch,
        components_to_update: List[str],
    ) -> Mapping[str, Sequence[Mapping[str, Any]]]:
        traces = eval_batch.trajectories or []
        failures = [t for t in traces if t["score"] < 1.0]
        chosen = failures or traces
        out: Dict[str, List[Dict[str, Any]]] = {}
        for name in components_to_update:
            records = []
            for trace in chosen:
                records.append(
                    {
                        "Inputs": {
                            "The brief the critic judged": shorten(trace["brief"]),
                            "The section under rewrite": candidate.get(name, ""),
                        },
                        "Generated Outputs": shorten(trace["reply"], 500),
                        "Feedback": feedback(trace),
                    }
                )
            out[name] = records
        return out


def shorten(text: str, limit: int = 900) -> str:
    """Keep a long brief readable for the model that rewrites."""
    words = text.split()
    if len(words) <= limit:
        return text
    head = " ".join(words[: int(limit * 0.6)])
    tail = " ".join(words[-int(limit * 0.4):])
    return f"{head}\n\n[... {len(words) - limit} words cut from the middle ...]\n\n{tail}"


def feedback(trace: Mapping[str, Any]) -> str:
    """What the rewriting model is told about one case."""
    if trace["score"] >= 1.0:
        return f"Correct. The expected verdict was {trace['expected']}."
    got = trace["verdict"] or "no verdict at all"
    lines = [f"Wrong. The expected verdict was {trace['expected']}, and the critic said {got}."]
    if trace["expected"] == "APPROVE":
        lines.append(
            "This Plan is sound. The critic invented an objection, and that costs "
            "a round trip of a person's attention."
        )
    else:
        lines.append("This Plan has a real defect. The critic missed it.")
    if trace.get("category"):
        lines.append(f"The defect in this brief is of the kind `{trace['category']}`.")
    return " ".join(lines)


# ------------------------------------------------------------------ the lock


class FreeOnlyRoundRobin:
    """Round robin over the free sections, and over nothing else.

    GEPA's own selector cycles every key of the candidate. This one cycles
    the free list, so a locked section is never proposed for.
    """

    def __init__(self, free: Sequence[str]):
        self.free = list(free)
        if not self.free:
            raise ValueError("no free section: there is nothing to search")
        self._next: Dict[int, int] = {}

    def __call__(self, state, trajectories, subsample_scores, candidate_idx, candidate):
        pid = self._next.get(candidate_idx, 0) % len(self.free)
        self._next[candidate_idx] = (pid + 1) % len(self.free)
        name = self.free[pid]
        assert name in candidate, f"free section missing from the candidate: {name}"
        return [name]


# ------------------------------------------------------- the rewriting model

SECTION_BEGIN = "=== THE SECTION UNDER REWRITE (BEGIN) ==="
SECTION_END = "=== THE SECTION UNDER REWRITE (END) ==="

REFLECTION_TEMPLATE = f"""You improve one section of a review prompt. The prompt is the system
prompt of a critic that gates a hand-written change Plan before an unattended
build runs against it. You see one section of it, and cases the critic judged
wrongly with that section in place.

{SECTION_BEGIN}
<curr_param>
{SECTION_END}

The cases below give the brief the critic judged, the critic's reply, and what
the right verdict was.

```
<side_info>
```

Write a better version of that one section.

Rules you must follow.

- You may cut, shorten, or reword. Shorter is better, as long as the verdicts
  hold. Do not add length for its own sake.
- You may not empty the section, and you may not cut it below about a third of
  its current length.
- Keep the voice of the prompt: short declarative sentences, second person,
  the same markdown shape. If the section starts with a bold label in a bullet,
  your version starts with the same bullet and the same label.
- Keep every category word the section names. The critic's output list uses
  those words, so a lost word breaks the report.
- Write nothing from a case into the section. No file name, no path, no
  identifier, no number, and no phrase taken from a brief. A rule that only
  fires on one of these cases is worthless. Write the general rule instead.
- Do not mention the cases, the feedback, or this exercise.

Return the new section, and nothing else, inside one ``` block."""


class ClaudeReflection:
    """The rewriting model: `claude -p` on one model, with no tools.

    GEPA calls this with the rendered prompt and expects the raw reply. A
    proposal that breaks a rule is thrown away here, by returning the
    section unchanged. GEPA then sees a child equal to its parent and drops
    it, which costs one reflection and no search damage.
    """

    NO_TOOLS = "Read Grep Glob Bash Task Agent Edit Write NotebookEdit WebFetch WebSearch"

    def __init__(
        self,
        model: str,
        shipped_text: str,
        log: Callable[[str], None] = print,
        runner: Callable[[str], str] | None = None,
        sleeper: Callable[[float], None] = time.sleep,
    ):
        self.model = model
        self.shipped_words = tokens(shipped_text)
        self.log = log
        self._runner = runner or self._claude
        self._sleep = sleeper
        self.rejected = 0
        self.calls = 0

    def _claude(self, prompt: str) -> str:
        sandbox = tempfile.mkdtemp(prefix="hone-reflect-")
        try:
            proc = subprocess.run(
                ["claude", "-p", prompt, "--model", self.model, "--safe-mode",
                 "--disallowedTools", self.NO_TOOLS, "--output-format", "json"],
                cwd=sandbox, capture_output=True, text=True,
            )
            if proc.returncode != 0:
                return ""
            env = json.loads(proc.stdout)
            if env.get("is_error"):
                return ""
            return env.get("result") or ""
        except Exception:
            return ""
        finally:
            shutil.rmtree(sandbox, ignore_errors=True)

    def __call__(self, prompt: Any) -> str:
        text = prompt if isinstance(prompt, str) else json.dumps(prompt)
        original = between(text, SECTION_BEGIN, SECTION_END)
        attempt = 0
        while True:
            raw = self._runner(text)
            self.calls += 1
            if raw.strip():
                proposal = fenced(raw)
                bad = self.violation(original, proposal, text)
                if bad is None:
                    return raw
                self.rejected += 1
                self.log(f"proposal thrown away: {bad}\n  it began: {proposal[:160]!r}")
                return f"```\n{original}\n```"
            wait = backoff(attempt)
            self.log(
                f"the rewriting model gave nothing on try {attempt + 1}. This "
                f"looks like the plan's usage limit. Waiting {wait}s, then "
                "trying again."
            )
            self._sleep(wait)
            attempt += 1

    def violation(self, original: str, proposal: str, rendered: str) -> str | None:
        """Say why a proposal is unusable, or None when it is fine."""
        if not proposal.strip():
            return "it is empty"
        floor = max(MIN_WORDS, int(MIN_WORD_SHARE * word_count(original)))
        if word_count(proposal) < floor:
            return f"it is under the floor of {floor} words"
        cases = strip_section(rendered).replace(original.strip(), " ")
        leaked = self._leaked_tokens(proposal, cases) - names(original)
        if leaked:
            return f"it copies a name or a value from a case: {sorted(leaked)[:6]}"
        phrase = copied_phrase(proposal, cases, original)
        if phrase:
            return f"it copies a phrase from a case: {phrase!r}"
        return None

    def _leaked_tokens(self, proposal: str, cases: str) -> set:
        """Names and values the proposal took from a case.

        The rendered reflection prompt holds the briefs. A NAME in the
        proposal that one of those briefs uses, and that the shipped prompt
        never uses, is case content written into the prompt.

        Only a name counts, never an ordinary English word. A brief and a
        prompt about reviewing Plans share most of their vocabulary, so a
        rule on plain words would throw away nearly every proposal. A leak
        reads as a path, an identifier, a number, or a proper noun, and
        `names` finds exactly those.
        """
        return {w for w in names(proposal) - self.shipped_words if w in tokens(cases)}


COMMON = set(
    """about above across after again against already also although always among
    another answer anything apply area areas asks avoid because become been before
    behind being below better between beyond both build builds building came cannot
    carry case cases change changes check checks choice claim claims clear code
    concrete could demand describe design detail details does doing done during
    each earlier either else enough equally even ever every exact example except
    exist expect fact fail fails file files find first flag following forces form
    format from full general give given goes good great group half hand hard have
    help here hold holds however idea identify inside instead into issue item items
    itself just keep kind know known land large last later least leave less level
    like line lines list little live long look loses made make makes many matter
    mean means might more most move much must name named names need needs never
    next nothing number numbers office often once only open opens order other
    others otherwise over owns part parts pass past people person pick place plan
    plans point possible present press proof prove proves provide question quite
    rather read reads real really reason record refer reject rejects relies remain
    remove removes report reports require result return right rule rules runs same
    says second section sections seem sees sentence separate set sets several shape
    share short should show shows side signal since single small some something
    sort speak specific stage stand start state states stay step steps still stop
    such take taken tell tells test tests text than that them then there these they
    thing think this those though three through time times today together told took
    toward true turn turns twice under until upon usual value values very want
    wants ways well were what when where whether which while whole whose will with
    within without word words work works worth would write writes wrong your""".split()
)


def common(word: str) -> bool:
    return word in COMMON


def between(text: str, start: str, end: str) -> str:
    i = text.find(start)
    j = text.find(end)
    if i < 0 or j < 0:
        return ""
    return text[i + len(start): j].strip("\n")


def fenced(raw: str) -> str:
    """The text of the last fenced block, as GEPA's own extractor reads it."""
    start = raw.find("```")
    end = raw.rfind("```")
    if start < 0 or start >= end:
        return raw.strip()
    body = raw[start + 3: end]
    if "\n" in body:
        first, rest = body.split("\n", 1)
        if not first.strip() or first.strip().isalpha():
            body = rest
    return body.strip("\n")


def leak_report(text: str, brief_dirs: Iterable[str], shipped_text: str) -> tuple:
    """What `text` shares with a private brief and the shipped prompt lacks.

    Phase D runs this over every candidate before a person copies it into
    the repository, because private material may not enter git. It returns
    two lists, and they have different jobs.

      * `names` is a path, an identifier, a number, or a proper noun. Each
        one is a real leak. A script may refuse the copy on it.
      * `words` is ordinary English. A brief and a review prompt share most
        of their vocabulary, so this list is long and almost always
        harmless. A person reads it. No script acts on it.
    """
    shipped = tokens(shipped_text)
    mine = tokens(text) - shipped
    mine = {w for w in mine if not common(w)}
    suspect = names(text) - names(shipped_text) - shipped
    found, found_names = set(), set()
    for directory in brief_dirs:
        for path in pathlib.Path(directory).rglob("brief.md"):
            in_brief = tokens(path.read_text(encoding="utf-8"))
            found |= mine & in_brief
            found_names |= suspect & in_brief
    return sorted(found_names), sorted(found - found_names)
