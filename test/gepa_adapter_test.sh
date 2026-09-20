#!/bin/bash
# Plumbing test for the prose search (evals/optimize/adapter.py).
#
# No model call and no network. A stub stands in for every call, so this test
# proves the parts that a wrong search would get silently wrong:
#
#   * the lock: a locked section may not change, and a free one may not empty
#   * the assembly: a candidate joins back into the shipped file byte for byte
#   * the score map: 1 for the right verdict, 0 for the wrong one, and the
#     per-objective scores present only on the label they belong to
#   * the error rule: an empty reply is retried, and never scored as 0
#   * the word count: shorter scores higher, and the shipped prompt scores 0.5
#   * the leak guard: a proposal that copies case content is thrown away
#
# It skips cleanly when the `gepa` package is not available offline, because
# the adapter imports `gepa.core.adapter`.
#
# Run: bash test/gepa_adapter_test.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${UV_PROJECT_ENVIRONMENT:=/var/tmp/hone-optimize/venv}"
export UV_PROJECT_ENVIRONMENT PYTHONDONTWRITEBYTECODE=1

command -v uv >/dev/null 2>&1 || { echo "SKIP gepa_adapter_test.sh: no uv"; exit 0; }
if ! uv run --project "$ROOT/evals/optimize" --offline python -c "import gepa" >/dev/null 2>&1; then
    echo "SKIP gepa_adapter_test.sh: gepa is not installed and the network is off"
    echo "  install it once with: uv sync --project evals/optimize"
    exit 0
fi

uv run --project "$ROOT/evals/optimize" --offline python - "$ROOT" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / "evals/optimize"))
import adapter as A
import sections

fails = []


def check(name, cond, detail=""):
    if cond:
        print(f"ok   {name}")
    else:
        print(f"FAIL {name} {detail}")
        fails.append(name)


PROMPT = str(root / "agents/plan-critic.md")
free, locked = A.load_locks(str(root / "evals/optimize/locks.json"), "plan-critic")
out = pathlib.Path("/tmp/hone-gepa-test-prompts")
assembler = A.PromptAssembler(PROMPT, free, str(out))
seed = assembler.seed_candidate()

# --- the lock and the assembly -----------------------------------------

check("every free section is in the prompt", all(n in seed for n in free))
check("free and locked cover the candidate",
      set(free) | set(locked) == set(seed),
      f"missing: {set(seed) - set(free) - set(locked)}")
check("frontmatter is no component", not any(n.startswith("_") for n in seed))
check("the seed candidate rebuilds the shipped file byte for byte",
      assembler.assemble(seed) == sections.read_file(PROMPT))

bad = dict(seed)
bad[locked and sorted(locked)[0]] = "rewritten by the search"
try:
    assembler.assemble(bad)
    check("a changed locked section is refused", False)
except A.LockedSectionError:
    check("a changed locked section is refused", True)

emptied = dict(seed)
emptied[free[0]] = "   "
try:
    assembler.assemble(emptied)
    check("an emptied free section is refused", False)
except A.LockedSectionError:
    check("an emptied free section is refused", True)

tiny = dict(seed)
tiny[free[0]] = "- **Slug collision.** Reject a nested slug."
try:
    assembler.assemble(tiny)
    check("a free section under the floor is refused", False)
except A.LockedSectionError:
    check("a free section under the floor is refused", True)

# The rewriting model returns prose and drops the blank line that ends a
# section. Without the repair, the next bullet or the next heading glues
# onto the last sentence, and a glued `## Output` stops being a heading.
stripped = dict(seed)
stripped[free[0]] = seed[free[0]].rstrip()
rebuilt = assembler.assemble(stripped)
check("a section that lost its trailing newline is repaired",
      rebuilt == sections.read_file(PROMPT))
check("no heading is glued to a sentence",
      "\n## Output" in rebuilt and rebuilt.count("\n## ") == sections.read_file(PROMPT).count("\n## "))

shorter = dict(seed)
words = seed[free[0]].split()
shorter[free[0]] = " ".join(words[: int(len(words) * 0.7)])
try:
    assembler.assemble(shorter)
    check("a shortened free section is allowed", True)
except A.LockedSectionError as exc:
    check("a shortened free section is allowed", False, str(exc))

# --- the component selector only ever offers a free section ------------

selector = A.FreeOnlyRoundRobin(free)
picked = [selector(None, [], [], 0, seed)[0] for _ in range(len(free) * 3)]
check("the selector picks only free sections", set(picked) <= set(free))
check("the selector reaches every free section", set(picked) == set(free))

# --- the score map and the objectives ----------------------------------

CASES = pathlib.Path("/tmp/hone-gepa-test-cases")
for name, expected in (("approve-one", "APPROVE"), ("reject-one", "REJECT")):
    d = CASES / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "brief.md").write_text("A short brief.\n")
    (d / "expected").write_text(expected + "\n")

batch = [
    A.Item("approve-one", str(CASES / "approve-one"), "APPROVE", "field", ""),
    A.Item("reject-one", str(CASES / "reject-one"), "REJECT", "generated", "slug-collision"),
]


class Stub:
    """Stands in for measure.sh. Counts rounds and replies to order."""

    def __init__(self, script):
        self.script = list(script)
        self.rounds = 0
        self.seen = []

    def __call__(self, prompt_file, items):
        self.rounds += 1
        self.seen.append([i.id for i in items])
        replies = self.script.pop(0) if self.script else {}
        return {i.id: replies.get(i.id, "") for i in items}


class NoCache(A.ReplyCache):
    def get(self, *a):
        return None

    def put(self, *a):
        return None


slept = []
stub = Stub([{"approve-one": "VERDICT: APPROVE", "reject-one": "VERDICT: APPROVE"}])
task = A.PlanCriticAdapter(assembler, str(root), "test-model", NoCache("/tmp/hone-gepa-test-cache"),
                           log=lambda m: None, runner=stub, sleeper=slept.append)
result = task.evaluate(batch, seed, capture_traces=True)

check("a right verdict scores 1", result.scores[0] == 1.0)
check("a wrong verdict scores 0", result.scores[1] == 0.0)
check("approve_right is only on an APPROVE item",
      "approve_right" in result.objective_scores[0] and "approve_right" not in result.objective_scores[1])
check("reject_right is only on a REJECT item",
      "reject_right" in result.objective_scores[1] and "reject_right" not in result.objective_scores[0])
check("words rides on every item", all("words" in o for o in result.objective_scores))
check("traces carry the brief and the reply",
      result.trajectories[0]["brief"].startswith("A short brief") and result.trajectories[1]["score"] == 0.0)
check("the metric count is the calls made", result.num_metric_calls == 2)

# --- the word objective -------------------------------------------------

check("the shipped prompt scores 0.5 on words",
      abs(result.objective_scores[0]["words"] - 0.5) < 0.01,
      str(result.objective_scores[0]["words"]))

cut = dict(seed)
for name in free:
    body = seed[name].split()
    cut[name] = " ".join(body[: max(A.MIN_WORDS + 2, int(len(body) * 0.4))]) + "\n\n"
stub2 = Stub([{"approve-one": "VERDICT: APPROVE", "reject-one": "VERDICT: REJECT"}])
task2 = A.PlanCriticAdapter(assembler, str(root), "test-model", NoCache("/tmp/hone-gepa-test-cache"),
                            log=lambda m: None, runner=stub2, sleeper=slept.append)
short_result = task2.evaluate(batch, cut, capture_traces=False)
check("a shorter prompt scores higher on words",
      short_result.objective_scores[0]["words"] > result.objective_scores[0]["words"])

# --- an infrastructure error is never a 0 -------------------------------

slept.clear()
outage = Stub([
    {},                                                        # the whole batch died
    {},                                                        # and again
    {"approve-one": "VERDICT: APPROVE", "reject-one": "VERDICT: REJECT"},
])
task3 = A.PlanCriticAdapter(assembler, str(root), "test-model", NoCache("/tmp/hone-gepa-test-cache"),
                            log=lambda m: None, runner=outage, sleeper=slept.append)
recovered = task3.evaluate(batch, seed, capture_traces=False)
check("an outage is retried, not scored", outage.rounds == 3 and len(slept) == 2)
check("the retry scores the real verdicts", recovered.scores == [1.0, 1.0])

# The plan's usage limit is the case this path exists for. Several workers
# share one plan, so the limit hits during a long search and holds for
# hours. The wait must therefore have NO cap.
slept.clear()
logged = []
rounds = len(A.BACKOFF) + 6
limit = Stub([{} for _ in range(rounds)]
             + [{"approve-one": "VERDICT: APPROVE", "reject-one": "VERDICT: REJECT"}])
task_limit = A.PlanCriticAdapter(assembler, str(root), "test-model",
                                 NoCache("/tmp/hone-gepa-test-cache"),
                                 log=logged.append, runner=limit, sleeper=slept.append)
after_limit = task_limit.evaluate(batch, seed, capture_traces=False)
check("a usage limit longer than the backoff list never gives up",
      limit.rounds == rounds + 1 and after_limit.scores == [1.0, 1.0],
      f"rounds {limit.rounds}, scores {after_limit.scores}")
check("every wait writes one log line", len(logged) == rounds and len(slept) == rounds,
      f"{len(logged)} lines, {len(slept)} waits")
check("the wait grows and then holds, and never shrinks",
      slept == sorted(slept) and slept[-1] == A.BACKOFF[-1],
      str(slept))
check("the limit is named in the log", all("usage limit" in line for line in logged))

# a single case that will not answer, while the rest of the batch does
partial = Stub([
    {"approve-one": "VERDICT: APPROVE"},
    {"approve-one": "VERDICT: APPROVE"},
    {"approve-one": "VERDICT: APPROVE"},
    {"approve-one": "VERDICT: APPROVE"},
])
slept.clear()
task4 = A.PlanCriticAdapter(assembler, str(root), "test-model", NoCache("/tmp/hone-gepa-test-cache"),
                            log=lambda m: None, runner=partial, sleeper=slept.append)
stubborn = task4.evaluate(batch, seed, capture_traces=False)
check("one silent case gives up after a few rounds and the rest still score",
      stubborn.scores[0] == 1.0 and stubborn.scores[1] == 0.0 and partial.rounds <= 4)

# --- the leak guard on a proposal ---------------------------------------

shipped = assembler.shipped_text
reflect = A.ClaudeReflection("test-model", shipped, log=lambda m: None,
                             runner=lambda p: "", sleeper=slept.append)
rendered = (
    f"{A.SECTION_BEGIN}\n{seed[free[0]]}\n{A.SECTION_END}\n"
    "Example 1\nThe brief names src/widgets/zephyrcache.py and the flag "
    "ENABLE_ZEPHYR_MODE in its migration.\n"
    "The owner of the area must decide whether the stored rows survive the move.\n"
)
COPIED = "the owner of the area must decide whether the stored rows survive"
clean = (
    "- **Slug collision.** Compare the Plan's slug with the slug of every open Plan. "
    "Do this even when the two changes share no file, because the check is about "
    "names. Reject a slug nested under an open slug, or one that names a directory "
    "holding other open Plans. Such a Plan reads as a reference file and drops out "
    "of the pending scans."
)
leaky = clean + " For example, reject a slug under src/widgets/zephyrcache.py."
phrasey = clean + " " + COPIED + " the move."
check("a clean proposal passes the guard",
      reflect.violation(seed[free[0]], clean, rendered) is None,
      str(reflect.violation(seed[free[0]], clean, rendered)))
check("a proposal that copies a name is refused",
      "a name or a value" in (reflect.violation(seed[free[0]], leaky, rendered) or ""),
      str(reflect.violation(seed[free[0]], leaky, rendered)))
check("a proposal that copies a phrase is refused",
      "a phrase" in (reflect.violation(seed[free[0]], phrasey, rendered) or ""),
      str(reflect.violation(seed[free[0]], phrasey, rendered)))
# The reflective dataset repeats the section under rewrite in every record,
# so the rendered prompt holds it twice. Its own sentences are not a leak.
doubled = rendered + "\n### The section under rewrite\n" + seed[free[0]] + "\n"
check("the section's own words are no leak, even when the prompt repeats them",
      reflect.violation(seed[free[0]], seed[free[0]], doubled) is None,
      str(reflect.violation(seed[free[0]], seed[free[0]], doubled)))

ordinary = clean + " A nested slug overlaps another Plan and nests inside it."
check("an ordinary English word shared with a case is not a leak",
      reflect.violation(seed[free[0]], ordinary, rendered) is None,
      str(reflect.violation(seed[free[0]], ordinary, rendered)))
check("an empty proposal is refused",
      reflect.violation(seed[free[0]], "  ", rendered) is not None)
check("a proposal under the floor is refused",
      reflect.violation(seed[free[0]], "- **Slug collision.** No.", rendered) is not None)

# The rewriting model sits on the same plan, so its limit is the same limit.
slept.clear()
quiet = [""] * (len(A.BACKOFF) + 5) + ["```\n" + clean + "\n```"]
logged2 = []
patient = A.ClaudeReflection("test-model", shipped, log=logged2.append,
                             runner=lambda p: quiet.pop(0), sleeper=slept.append)
answer = patient(rendered)
check("the rewriting model waits out a long limit too",
      clean in answer and len(slept) == len(A.BACKOFF) + 5,
      f"{len(slept)} waits")
check("each of its waits writes one log line naming the limit",
      len(logged2) == len(slept) and all("usage limit" in line for line in logged2))

# the rewriting model that gives nothing is retried, not accepted
slept.clear()
answers = ["", "", "```\n" + clean + "\n```"]
reflect2 = A.ClaudeReflection("test-model", shipped, log=lambda m: None,
                              runner=lambda p: answers.pop(0), sleeper=slept.append)
got = reflect2(rendered)
check("an empty rewrite is retried", len(slept) == 2 and clean in got)

# a leaky rewrite comes back as the original, so the child equals its parent
reflect3 = A.ClaudeReflection("test-model", shipped, log=lambda m: None,
                              runner=lambda p: "```\n" + leaky + "\n```", sleeper=slept.append)
kept = A.fenced(reflect3(rendered))
check("a leaky rewrite returns the section unchanged",
      kept.strip() == seed[free[0]].strip() and reflect3.rejected == 1)

print()
if fails:
    print(f"gepa_adapter_test.sh: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("gepa_adapter_test.sh: all green")
PY
