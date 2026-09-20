# Spike: labeled data for the `plan-critic`

**Date:** 2026-09-20 · **Status:** frozen. Written once, never maintained
against the code.

Step 2 of the handoff needs labeled data for the `plan-critic`. We tried a
public dataset first. It did not fit. The data we kept comes from real runs,
plus defects we injected on purpose.

## Part 1: Ambig-SWE, and why we dropped it

The paper is arXiv 2502.13069, accepted at ICLR 2026. The code and the data
live in the GitHub repository `sani903/InteractiveSWEAgents`, under the MIT
license. The data file is `full_summaries_verified.xlsx` at revision
`ed58236332ad039b54f968145d7bed9ba988f262`. It holds one row per SWE-bench
Verified instance, 500 in all. Each row carries the original GitHub issue and
a GPT-4o summary of it. The summary is the underspecified twin.

MIT allows this use. We still committed no dataset content, which is hone's
own rule for public material.

**The twenty-pair match.** I read twenty pairs at seed 20260920. For each one
I asked whether the information the summary drops is a fork that a person
must settle. Two matched well. Six matched in part. Twelve matched poorly.
The summarizer strips identity, not choice. It drops the library, the
function name, and the traceback. It keeps the decision. A builder with the
codebase can find what it dropped.

**The seed.** The shipped critic on claude-opus-5, one vote, on 50 pairs from
the train part. That is 100 briefs, and it cost 13.01 dollars of plan usage.
It was right on 47 of 50 underspecified twins, and on 18 of 50 fully
specified twins.

**Why we dropped it.** Read the second number before you believe it. Of the
32 wrong rejections, 29 lead with `placeholder`, and the finding is the
wrapper's own proof line. So the wrapper decided most of that row, not the
data. The deeper reason sits in the data. A GitHub bug report says what
broke. It rarely says what the fixed code must produce. Only 7 of the 50
original issues carry an expected-behaviour section. hone's Plan needs both
sides, so the critic rejects. Optimizing against that row would teach the
critic to approve a report that names no wanted output. That is the behavior
the critic exists to block. The dataset is dropped, and its scripts are
deleted.

## Part 2: the data we kept

### Method

`evals/optimize/data/` holds five scripts. Each takes the private paths as
arguments, so no consumer repository is named in this repository.

1. `from_sessions.py` recovers every `plan-critic` call from the stored
   subagent transcripts. The first user turn is the brief. The last assistant
   text is the report.
2. `field_briefs.py` makes each brief self-contained and labels it. An older
   brief shape names the Plan by path and tells the critic to read it. The
   script inlines that Plan, and every reference file, from the transcript's
   own `Read` results.
3. `mutate.py` injects one named defect into a clean brief. A model writes
   the mutation. It returns one anchor string and its replacement, never a
   whole brief. The script checks the anchor occurs once and applies it. So
   nothing else can change.
4. `split.py` merges both sets and splits them at a fixed seed.
5. `measure.sh` and `report.py` run a prompt over the set and score it.

**The label.** It starts as the production verdict. Hindsight then corrects
it, from the two field reports. Three approvals became `REJECT`. One petty
rejection became `APPROVE`. The index records the reason and the strength of
every corrected label.

**A caveat on every field label.** Every production run used
claude-sonnet-5. The shipped critic pins claude-opus-5 today. So a field
label is a sonnet verdict, and part of any disagreement is the model gap.
Another worker found that five of ten misjudgment shapes do not reproduce on
opus.

**The second look.** I read the injected edit of at least three cases per
bullet, 33 in all. I checked that the defect is real and material. I did not
have to check that nothing else changed, because the anchor mechanism
guarantees it.

### Counts

| source | items | APPROVE | REJECT |
| --- | --- | --- | --- |
| field, real runs | 140 | 120 | 20 |
| generated defects | 101 | 0 | 101 |
| generated harmless edits | 11 | 11 | 0 |
| **total** | **252** | **131** | **121** |

The field part holds 14 chains of more than one call, and 37 items sit in
one. A chain is a rejected draft and its revision, which is the most valuable
shape in the set. Four labels carry a hindsight correction.

The generated part covers all ten bullets under *What to hunt*, with 8 to 11
cases each. A harmless edit rewords one sentence or reorders two bullets. Its
label is `APPROVE`, so the set punishes a critic that rejects any change.

### The tools problem

In production the critic has `Read`, `Grep`, and `Glob`, and it checks each
citation against the repository. `evals/run.sh` calls it with no tools in an
empty directory. I ran the shipped critic on 20 real briefs, one vote, on
claude-opus-5. Ten carried a `REJECT` label and ten an `APPROVE` label.

It agreed with the production verdict on 15 of 20. Sixteen of the 20 replies
opened with a paragraph about the missing file access. Of the five
disagreements, three came from the missing tools:

- Two production rejections rested on a fact that only a file read gives. One
  critic opened a file and found a sentence boundary mid-line. The offline
  call cannot reach either fact, so it approved.
- One offline call rejected because a reference file was out of reach.

The other two disagreements are real differences of judgment. The offline
call found an arithmetic contradiction inside the brief that the production
call had passed.

**The fix we built.** Two of them, and both are cheap.

The first is a fixed preface in the user turn. It tells the critic three
things. The review is offline. Every citation in the brief is already
verified. The lack of access is not a finding. It removed the caveat from
every reply, 16 of 20 down to 0 of 20. It did not move agreement, which went
from 15 to 14 of 20. That is inside the noise of one vote. We adopted it
anyway. A reflective optimizer reads the reply text, and a caveat paragraph
in every trace is noise it would try to write away. `split.py` writes the
preface into each brief, so it needs no flag on `evals/run.sh`.

The second fix matters more and came free. `field_briefs.py` inlines the Plan
and its reference files from the transcript. 114 of 140 briefs needed the
Plan inlined, and 71 needed a reference.

**We did not build the throwaway clone.** It needs a clone per brief across
four private repositories, at the right commit. It would also carry private
content into the search loop. The preface costs nothing and fixes the part
that the clone would fix.

### Does a bullet's cases aim at that bullet?

`discriminate.sh` runs each bullet's generated cases twice. Once on the full
prompt, and once on the prompt with that bullet cut. The cut removes the
bullet's category word from the *Output* list too, per the rule of
2026-09-18. One vote per call, on claude-opus-5.

| bullet | cases | full right | minus right | flipped |
| --- | --- | --- | --- | --- |
| slug-collision | 11 | 11 | 3 | 8 |
| missing-baseline | 11 | 4 | 5 | 5 |
| prose doing an artifact's job | 10 | 6 | 3 | 3 |
| ambiguity | 10 | 6 | 4 | 2 |
| contract-churn | 11 | 11 | 9 | 2 |
| placeholders | 10 | 7 | 9 | 2 |
| contradictions | 10 | 9 | 8 | 1 |
| collision with an open change | 8 | 7 | 7 | 0 |
| dependency and toolchain refreshes | 10 | 10 | 10 | 0 |
| scope | 10 | 10 | 10 | 0 |

Read it in four groups.

*Load-bearing.* `slug-collision` carries its cases outright. Without the
bullet, opus approves 8 of the 11 nested slugs. `prose doing an artifact's
job`, `ambiguity`, and `contract-churn` each lose ground without their
bullet. Step 6 may free all four from the lock.

*Load-bearing and still wrong.* `missing-baseline` flips five cases, so the
bullet moves the answer. It is right on only 4 of 11 either way. The bullet
is doing something, and not the right thing.

*The bullet may hurt.* `placeholders` gets two cases right without its
bullet that it gets wrong with it. The cases are easy for opus, and the
bullet pulls it off them.

*No signal.* `scope`, `collision with an open change`, and `dependency and
toolchain refreshes` are right on every case with and without their bullet.
Either opus needs no such bullet, or these cases are too easy. The verdicts
were unanimous and quick, so read it as cases that are too easy. Those three
bullets keep their lock until a harder case exists.

### The split

`split.py` splits at seed 20260920. The unit is a group, not a case. A chain
stays whole, and every mutation of one source brief stays with that source. A
group built from hone's own visible cases goes to validation.

| part | cases | APPROVE | REJECT | field | generated |
| --- | --- | --- | --- | --- | --- |
| train | 143 | 79 | 64 | 91 | 52 |
| validation | 58 | 28 | 30 | 25 | 33 |
| holdout | 51 | 24 | 27 | 24 | 27 |

That is 118 groups. The ID files are `train.ids`, `validation.ids`, and
`holdout.ids` beside the cases.

### The seed

The shipped prose, one vote per case, over train and validation together.

| model | label | right | of | percent |
| --- | --- | --- | --- | --- |
| claude-opus-5 | APPROVE | 77 | 107 | 72 |
| claude-opus-5 | REJECT | 72 | 94 | 77 |
| claude-sonnet-5 | APPROVE | 86 | 107 | 80 |
| claude-sonnet-5 | REJECT | 68 | 94 | 72 |

Per part, on opus: train is 76 percent on `APPROVE` and 73 percent on
`REJECT`. Validation is 61 percent and 83 percent. On sonnet: train is 82 and
70 percent, validation 75 and 77 percent.

The handoff's stop rule asks for more than 90 percent on both labels. No cell
comes near it. There is headroom on both models.

Split by source, on opus. The critic is right on 69 of 97 field approvals and
11 of 19 field rejections. It is right on 61 of 75 injected defects and 8 of
10 harmless edits. So the field part is the harder half, and the field
rejections are the hardest quarter of the set.

Sonnet beats opus on the field part and loses to it on the generated part.
Read that with the model caveat above. A field label is a sonnet verdict, so
sonnet is being scored against its own kind of answer.

### Cost

About 112 dollars of plan usage in all. The mutations cost 4 dollars on
claude-sonnet-5. The rest went on claude-opus-5. That is 14 dollars for the
tools probe and 23 for the full-prompt pass over the generated cases. The ten
ablation passes cost 27, and the field seed 34. The sonnet seed over 201 cases
cost 10 dollars. One `plan-critic` call on a real field brief costs about 30
cents on opus and about 5 cents on sonnet.

### Limits

One vote per case everywhere, so the noise floor of `evals/README.md` does
not apply. A single flipped verdict in the table above may be sampling noise.
Re-measure at three votes before a claim rests on one row.

The field labels are sonnet verdicts, corrected by two hand-written reports.
A Plan that was approved and simply worked leaves no trace of a near miss, so
the count of wrong approvals is a lower bound.
