# Spike: what the evals and the lab bought

**Date:** 2026-09-27 · **Status:** frozen. Written once, never maintained
against the code.

## Question

From 2026-08-27 to 2026-09-20, much of the work on hone went into the unit
suites (`evals/`), the scenario lab (`evals/lab/`), and the probes. Did that
work make hone better, compared with the other sources of fixes?

## Method

Four agents read four sources, and I checked the claims that decide the
outcome against git and the transcripts.

- The git history of hone: 480 commits since 2026-07-09. 200 of them touch the
  shipped plugin. Each commit got a trigger from its message, its release
  body, and the spikes.
- The maintainer's hone sessions from 2026-08-27 on: 21 real sessions. About
  156 more files are stub sessions that the harness spawned. There are no
  transcripts from before 2026-08-27.
- The transcripts of the private consumer repository with the most use: 154
  sessions, grouped by the hone version that each started on.
- Three more consumer repositories. None has a commit or a session after
  2026-09-01, so they give a baseline and no comparison.

The shares by trigger come from reading commit prose. A commit can fit two
classes, so read each share as rough.

## Results

### Where the fixes came from

Of the 200 product commits, about 15 (8%) had an eval, the lab, or a probe as
their trigger. About 45% came from real use, 30% from the maintainer's design,
and 12% from code review. Every lab trigger but two falls on 2026-09-17 to
2026-09-19. The releases 0.59.1 to 0.65.0 came almost only from the field
notes of 2026-09-20 and 2026-09-25.

### What the evals and the lab caught

- Defects found before release, on 2026-09-17 to 09-19. The nested review ran
  at a saved `low` level (b0a879d). The plan-critic approved a fork that
  the author had left open (d947ddf). Runs merged into main by hand in 4 of 5
  (6378a13). Sessions ended empty after nine gate blocks (8b827af, 75418fb).
  Also smaller defects: the claim refusal, review paths that collided, and a
  false "landed" line.
- Regressions blocked at the gate. On 2026-08-27 a critic edit fell from 5/5
  to 3/16 on the unit suite. On 2026-09-17 four lab scenarios failed a
  run-skill edit that the loop suite passed at 3/3. On 2026-09-25 the lab
  showed that a prose fix for progress lines did not work. The hook in 0.64.0
  then gave 6 of 6.
- Measures of hone's claim. Transparency held in 30 of 30 runs against 2 of
  10 in a bare session. On ImpossibleBench, bare opus cheated on 5 to 7 of 10
  tasks, and hone on 1 of 10.

### What they did not do

- Green gates missed real defects. 0.62.0 passed the lab at 21/21 and every
  unit suite. A code review then found about 20 routes past the `bash-guard`,
  and 0.62.1 reverted it. The first fix for the double review made it worse
  behind a green pass. Only the transcripts showed it.
- The lab and a loop case pinned the agent granting itself at the authority
  gate. The field showed 11 grants and no catch, and 0.64.0 reversed it.
- The 0.58.0 ask on moves of the primary branch came from a probe. In the
  field it made about 3 right calls to 11 false ones, and four releases
  settled it.
- Two section-ablation campaigns cut nothing. The one prose cut that shipped
  (90f280b) rested on single votes.
- On opus the benchmarks have no room. The review bench scores 51 of 51. Six
  of seven adversarial scenarios pass with the guards off. Of 10 field
  misjudgments made into cases, 5 vanished on opus and 3 pinned nothing.
- Every unit measurement before 2026-08-27 is unsound, because the harness
  could read the answer key. At least four lab fails were bugs in a check.

### What it cost

In week 38, about 70% of commits were harness work: 61 eval-only against 22
product-only. The `evals/` tree holds about 35k lines, the plugin about 11k.
The spikes record at least 550 dollars of model spend. A lab pass costs about
40 dollars and 65 minutes. The campaigns of 2026-09-20 hit the plan's session
and weekly limits and stopped half done.

### The consumer repository, before and after

Friction fell after the fixes of 0.62 and 0.63, which came from the field
notes. `bash-guard` asks went from 14.9 to 5.0 per 1000 shell commands. The
`nag`'s false link line went from 631 of 633 stops to 4 of 250. Stalls on the
mutation config and suite-lock blocks that blamed "another session" stopped.
No window had a revert or a complaint about hone. The plan-critic rejected
about 48% of Plans before and after, and the sampled rejects were real. Only 4
sessions ran on 0.64 or 0.65, too few to judge those releases.

### Defects found in the field that no suite caught

- The test-first rule of the guard asks for a test of a fixture file under
  `src/`. 5 of 6 test-first denies were on fixtures, and the agent wrote a
  test for each one.
- A land that succeeds returns exit code 1 when the shell stands in the
  worktree that land removed. 8 sessions show it, some on 0.63.0.
- 41 of 76 field `bash-guard` asks still ask when replayed on 0.65.
- 0.65.0 counts a table rewrite as lossless only with a `SELECT *` copy.
  Atlas writes the copy with a column list, so each field fire of the
  authority gate still fires.

## Decision

The evals and the lab are worth keeping as a regression gate, and not as the
source of work. Real use found more defects and worse ones, for less money.
On 2026-09-27 the maintainer decided:

- Field transcripts are the main source of work. Each fix of a field shape
  ships with a test or a scenario that replays the shape.
- A guard change gets a code review before release.
- The mechanical suite (`test/`), the unit suites, and the lab gate stay.
  So do the transparency and cheating measures, as a periodic check.
- No new benchmark, probe, ablation campaign, prompt search, or noise-floor
  measurement starts without the maintainer's word. This drops the
  optimization program of `HANDOFF.md`, so its file goes, as it asked.
  So does its last brief, `.plans/optenv-5c-guards.md`. `git show
  c68f1fb:HANDOFF.md` reads the program. Comments in `evals/optimize/` and
  `evals/decision-points/` still name its steps.
- A new model gets one pass of the suites and the lab, and no floor,
  noise-floor, or watch-case re-measurement.
