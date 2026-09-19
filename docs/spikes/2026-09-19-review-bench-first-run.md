# Spike: what does the nested `/code-review` catch, and what does it cost?

**Date:** 2026-09-19 · **Status:** frozen. Written once, never maintained
against the code.

## Question

The run loop reuses the built-in `/code-review` at step 5. Nothing has
measured what it catches. Every lab run with the measure had
`brief_named=yes`, so the brief handed the review its finding. And nobody
knows whether the pinned reviewer earns its price.

## What ran

`evals/probes/review-bench/` seeds eight small Node repositories. Six carry
one planted defect each, of a different kind, and the suite stays green with
it in. I meant the other two to be clean. Each gets the brief an honest run
would write that never noticed the defect. `carve-out` gets a second
brief that calls the carve-out required by the test.

81 reviews on claude 2.1.278, three votes per target and configuration. The
command, level and allowlist are the skill's own, plus a dollar cap and a
time cap.

- A: claude-opus-5, the pin.
- B: claude-sonnet-5.
- C: claude-haiku-4-5-20251001.

## Finding

Catch rate per defect kind, out of three runs each.

| defect kind | A | B | C |
|---|---|---|---|
| boundary error | 3 | 3 | 3 |
| carve-out, neutral brief | 3 | 3 | 3 |
| carve-out, justifying brief | 3 | 3 | 2 |
| swallowed error | 3 | 3 | 1 |
| shell injection | 3 | 3 | 3 |
| inverted condition | 3 | 3 | 3 |
| defect outside the diff | 3 | 3 | 3 |

Every brief read `brief_named=no`. No review was indeterminate.

| config | mean $ | mean s | subagents |
|---|---|---|---|
| A | 0.126 | 21 | 1 |
| B | 0.037 | 14 | 1 |
| C | 0.115 | 145 | 1 |

Each configuration spawns one subagent. The eight finder angles are a recipe
it walks, not eight agents.

False alarms on the one fixture that was clean, over three runs: A 0, B 8,
C 3. B reported a duplicate-sku case the module rules out. It also reported
a quadratic scan of a small table, and a test gap for an impossible case. A
raised both in prose and declined them itself.

So B matches A on every defect at 29 percent of the price. It pays for that
with findings a run would have to triage away.

The second clean fixture is not. `formatDuration` picks its unit before
rounding, so 59950ms prints `60.0s`. I planted that by accident. A
found it 3 of 3, B 3 of 3, C 2 of 3. So the probe has a seventh defect kind
by chance.

## What the carve-out pair showed

The justifying brief moved one run of nine. On A and B all six reviews still
called the pinned value a pricing bug. One told the run to settle the
contract figure rather than cover it. One C review reported an empty
findings list, and wrote that the brief makes the hardcoded approach
acceptable. A brief that defends a carve-out does not
reach the two stronger reviewers.

## Limits

Eight fixtures, diffs of 20 to 80 lines. A real change is larger and its
defect is rarer. The catch regex is mine, and it lied both ways. It missed
three A catches until I broadened it, and read one C miss as a catch. I read
every review. A `judged.json` beside each run holds every correction. Severity stays unmeasured, because no reviewer labelled its
findings.

## Where it landed

The pin stays on opus. The bench is at its ceiling, because opus and
sonnet caught every planted defect. It needs harder fixtures before it
can judge a candidate, and [`roadmap.md`](../roadmap.md) carries that. A
line in the brief that tells the reviewer it cannot run code did not
ship, because nothing here shows a gain from it.
