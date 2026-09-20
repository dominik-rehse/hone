# Spike: one sequence scenario, seven Plans on one repository

**Date:** 2026-09-20 · **Status:** frozen. Written once, never maintained
against the code.

## Question

hone's claim is about the codebase after many changes. Every lab scenario
runs one change, so no scenario tests the claim. Step 4 of `HANDOFF.md`
asks for one that runs five to ten Plans in a row and grades only the end
state. Does such a scenario give room on the outcomes where opus sits at
the ceiling today?

## The design

### The fixture

A parcel depot in Python, about 260 lines of source and 120 of tests,
under `evals/lab/scenarios/one-sequence/`. Python, because `scb-check` is
Python only at 0.1.3
([`slopcodebench-first-look`](2026-09-18-slopcodebench-first-look.md)), and
it carries the `dup` and `cc_pile` measures. Six modules: the network
table, the parcel record, the price, the booking, the driver manifest, and
the label. `uv run pytest` is the adapter, and the suite runs offline in
under a second.

### The sequence

Seven briefs under `briefs/`, in the order of the `sequence` file. Each one
reads as a routine change of its own, and none names its trap.

| # | Change | The trap it sets or springs |
| --- | --- | --- |
| 1 | `depot/cutoff-time` | Its Notes ask for a Decision: one cutoff for the whole network. Change 5 makes that false. It also adds the first branch to `book_parcel`. |
| 2 | `depot/billable-weight` | Adds `billable_weight` in `pricing.py`. Change 6 needs the same rounding elsewhere. |
| 3 | `depot/counter-crib` | Writes `docs/counter-crib.md`, which names the cutoff, the free cover and the oversize weight. Changes 5 and 7 move two of the three. |
| 4 | `depot/hazardous-lane` | Three more branches in `book_parcel`. |
| 5 | `depot/depot-cutoffs` | One cutoff per depot. It stales the Decision of change 1 and the crib's cutoff line, and it adds two branches. |
| 6 | `depot/manifest-weights` | The manifest needs the billable weight, in another module than change 2 wrote it. |
| 7 | `depot/cover-raise` | The free cover goes from 500.00 to 1000.00 EUR. It stales the crib's cover line, and it adds two more branches. |

### The margins

`book_parcel` starts at cyclomatic complexity 3. Written inline, the four
branching changes take it to 13, and `scb-check` counts a function over 10.
Pulling its two concerns apart, the dispatch day and the lane, leaves three
functions at 2, 5 and 8. So the largest is two points clear of the line,
and a reasonable restructuring does not read as a pile.

The seed holds no structural clone, so `clone_loc` above 0 is one the
sequence wrote. The seed names 250 nowhere, so `weight_places` above 1 is a
second copy of the rounding.

### The hidden suite

Six files under `hidden/`. No fixture carries them, so no session read
them. Each names the change that owns its behaviour, which is the last
change it depends on. A change that did not land excuses its file. The
helper import in `test_billable_weight.py` searches every module of the
package. So a later refactor may move the helper, and the file still finds
it.

### The measures

`check.sh` makes hard checks of the mechanical half. The suite is green.
The run changed neither the adapter nor `pyproject.toml`. Every landed
change is one revertible commit. Every hidden file whose change landed
passes. The
outcomes are measures, as `evals/lab/README.md` prescribes for a scenario
that no run has held yet: `docs_true`, `dup`, `cc_pile`,
`weight_places`, `hidden_pass`, `landed_changes`, `crib` and
`cutoff_decision`.

I built both end states by hand and graded them before any model ran, as
*Writing a scenario* asks. A clean end state passes every check and reads
`dup=gone cc_pile=flat weight_places=1 docs_true=yes crib=true`. A decayed
one, with everything inline and the rounding copied, reads `dup=grown
cc_pile=piled weight_places=2 docs_true=no crib=stale`, with
`clone_loc=16` and `high_cc_functions=1`. So every measure discriminates
with no model call.

## The driver

`evals/lab/run.sh` gained `run_sequence`. A scenario with a `sequence` file
runs one session per change, in order, in one sandbox and on one
repository. The driver copies the brief into `.plans/`, commits it by
itself, and starts a fresh session on it. The budget and the timeout stay
per session. `result.json` carries the sum of the cost and the time, and
`steps.json` carries the numbers per change.

The rule on a stop: a session that lands nothing is a result, not a fault
of the harness, and it costs the person attention. The driver records it,
sets the brief aside in a commit of its own, and goes on with the next
change. The brief goes rather than stays, because a Plan left pending
changes what the next session reads, and both arms must meet the same
repository. An infrastructure failure is different. No result event, an
error envelope, a timeout or a spent budget stops the sequence, and the run
is indeterminate.

`test/lab_test.sh` proves all of this against the fake CLI. It runs three
stubbed sessions in a row. It reads the sums in `result.json`, a stop in
the middle, the turn per step on both arms, and a break mid-sequence.

One bug in the test itself is worth recording. `git log | grep -q` under
`set -o pipefail` reports the pipeline as failed, because `grep -q` closes
the pipe and `git` dies of SIGPIPE. The assertion looked wrong when the
driver was right.

## The runs

### Attempt 1, 2026-09-20

One run per arm on `claude-opus-5`, 7 sessions each, a 25 USD budget and a
25 minute timeout per session.

The bare arm passed everything that decides a verdict, and it moved only
one measure the wrong way.

| Measure | Bare |
| --- | --- |
| verdict | pass |
| cost, time | 3.53 USD, 11 min, 112 turns |
| `landed_changes` | 7/7 |
| `hidden_pass` | 6/6 |
| `docs_true` | yes |
| `crib` | true |
| `cc_pile` | flat |
| `weight_places` | 1 |
| `dup` | grown, `clone_loc` 6 |

The full arm died at step 2 on the plan's session limit, at 4.98 USD and
14 minutes. Step 1 alone cost 2.84 USD and took 9 minutes, against 0.39 USD
and under 2 minutes for the same change on the bare arm. So the one number
attempt 1 settles is the price: about seven times the dollars and six times
the minutes per change.

What the bare arm did, from its sandbox. It split `book_parcel` into
`cutoff_minute`, `dispatch_day`, `check_hazardous`, `check_declared_value`
and `book_parcel` itself, the largest at 7. It imported `billable_weight`
into the manifest rather than writing the rounding again. And it rewrote
`docs/counter-crib.md` at change 5 and again at change 7, so no literal in
it was false at the end. Its `dup=grown` came from a three-line pair of
parallel `if` blocks in `book_parcel`, not from the seeded trap.

So the traps were too easy, and for one reason: every one of them repeated
a literal of the code. A session that changes `FREE_COVER_CENTS` greps
`50000` and `500.00 EUR`, and it finds the crib sheet.

### What attempt 2 changed

Two traps that carry no literal of the code, and one more hidden file.

- The crib sheet of change 3 now carries three worked examples, word for
  word from the brief. One states the cutoff: `A parcel handed in at half
  past four goes out the next day`. Another names a value above the free
  cover: `A camera worth 600 EUR needs a declared value`. Change 5 makes the
  first false at two depots of three, and change 7 makes the second false.
  Neither sentence holds a constant of the code.
- The seed gained `src/depot/quotes.py`. The counter offers a declared
  value above `SUGGESTED_DECLARE_ABOVE_EUR`, held in whole euro because
  the till reads it over a wire that carries no import. Its comment says
  that it has to track the free cover. Change 7 raises the cover, and no
  brief names the file. `test_quote_advice.py` and the measure
  `quote_advice` read it.

The hand-built end states discriminate on both. A clean one reads
`hidden_pass=7/7 quote_advice=updated crib=true docs_true=yes`. A decayed
one reads `hidden_pass=6/7 quote_advice=stale crib=stale crib_examples=both
docs_true=no`, and it fails two checks.

### Attempt 2, 2026-09-20

One run per arm on `claude-opus-5`, same budget and timeout.

**A check that was wrong first.** The bare arm failed `docs_true`, and the
sandbox said why. It had rewritten the cutoff example. The new sentence
read "at half past four goes out the next day at BER, and the same day at
HAM and at MUC". That sentence is true. The first form of the check matched
the phrase, and a
corrected sentence keeps the phrase.

So the check now reads the claim around the phrase, not the phrase. A
sentence that keeps `half past four` is true only where it names a depot. A
sentence that keeps `600 EUR` is true only where it carries a negation.
`--regrade` applied the fix to the kept sandbox, at no cost. That is the
fourth time a lab fail came from a check and not from the run.

`docs_true` also moved from a check back to a measure. No run has held it on
this scenario, and `evals/lab/README.md` says a measure becomes a check only
after three runs of three.

| Measure | Bare, 7/7 | With hone, 6/7 |
| --- | --- | --- |
| verdict | pass | indeterminate |
| cost | 3.31 USD | 23.87 USD |
| time | 11 min | 70 min |
| `landed_changes` | 7/7 | 6/7 |
| `hidden_pass` | 7/7 | 5/7, two excused |
| `docs_true` | yes | yes |
| `crib` | true | true |
| `crib_examples` | some | both |
| `quote_advice` | updated | updated |
| `dup` | gone | gone |
| `cc_pile` | flat | flat |
| `weight_places` | 1 | 1 |
| `doc_pinned` | no | yes |

The run with hone lost step 7 to the plan's session limit. Attempt 1 had
lost step 2 the same way. I graded its six landed changes by hand, with the
same `check.sh`. Change 7 springs the cover trap, so two of the seven hidden
files are excused. `quote_advice` reads `updated` for want of a change
rather than for a fix.

**One measure moved between the arms, and it is a new one.** At change 3 the
run with hone wrote `tests/test_counter_crib.py`. It committed the page as
"add the counter crib, pinned to the code by tests". That made every claim
of the page executable: the cutoff example, the 600 EUR example, and the
oversize example. At change 7 those tests went red on the raised cover. The
transcript shows the run repairing the page and the tracking constant
together. Its line reads "the existing tests caught both downstream
figures". A page that no checker reads is what *Transparent* in
`docs/model.md` is about. So `doc_pinned` went into `check.sh` after the
run. A regrade of both sandboxes gave `yes` for hone and `no` for the bare
arm.

The bare arm reached the same end state by reading the repository each
time. It found `quotes.py` and it corrected the crib. It kept `book_parcel`
split into five functions, the largest at 7. It left nothing for a
checker.

## Conclusion

No room on the outcomes at this size, and a large gap on price.

On `claude-opus-5`, a bare session keeps a 300-line repository clean over
seven changes. It does so even against traps that carry no literal of the
code. Two attempts moved no outcome measure but `doc_pinned`. Step 4 of
`HANDOFF.md` says a scenario that both arms pass gives no room.

Three things this run does settle.

- The price. Seven changes cost 3.31 USD and 11 minutes with no hone.
  With hone, 6 of 7 changes cost 23.87 USD and 70 minutes. That is roughly
  seven times the dollars and six times the minutes per landed change. It
  is the widest arm gap any lab scenario has measured.
- `doc_pinned` is a real difference, and it is the kind step 4 was
  looking for. hone leaves a checker behind. A bare session leaves prose.
  The measure costs nothing, and it belongs in the other transparency
  scenarios too.
- A sequence run needs more than one session's worth of plan budget. Both
  attempts lost their hone arm to the session limit, once at step 2 and
  once at step 7. Run a sequence when the limit has just reset.

What the third attempt should be. Not a harder toy. The fixture is small
enough for one session to read whole, and that is why no trap survives. The
next attempt belongs on the *real bases* family of step 4. That means a
pinned repository of 5,000 to 20,000 lines, where reading it whole each
time is not an option. The scenario, the driver and the measures here carry
over unchanged. Only `seed.sh` and the briefs change.

Two smaller things for whoever picks this up.

- `dup` reads `clone_loc` against a seed of 0, so a three-line pair of
  parallel `if` blocks flips it to `grown`. That happened in attempt 1.
  `weight_places` is the seeded trap's own reading, and it is the one to
  trust.
- A worked example that a run corrects keeps its phrase. Read the claim
  around the phrase, never the phrase alone.



