# Handoff — field friction from the agent repo, post-0.6.0

Source: 18 Claude Code sessions in `~/repos/agent` (2026-07-14 → 2026-07-16),
mined after upgrading to hone 0.6.0. Two high-cost defects to fix, plus smaller
items from the same logs. Session ids reference
`~/.claude/projects/-home-dominik-repos-agent/<id>.jsonl`.

What worked and must not regress: the 0.6.0 land lock, exit-4 worktree claims,
and the exit-6 rollback all behaved exactly as designed in the field — three
parallel worktrees landed within 10 minutes with zero conflicts, and the one
rollback left the trunk green.

## 1. Full-suite runs race across sessions → phantom flakes and a spurious land exit 6

The land lock (`scripts/worktree.sh` `cmd_land`) serializes *lands against
lands*, but nothing serializes `scripts/run-tests.sh --all` invocations across
sessions: the gate's `--all` escalation (`hooks/gate.sh`, clean tree on a
`hone/*` branch), manual verify runs, and land's own re-verify all run
unsynchronized. Chromium e2e tiers are load-sensitive, so concurrent suites
poison each other's signal.

Field evidence (Jul 14, 19:05–20:00, two concurrent `/hone:run` sessions):

- Session `edf5ad67` burned ~55 minutes and ~6 full-suite runs chasing a
  browser-journey e2e "flake" that was pure contention — at one point racing
  main-vs-branch suites concurrently ("that's precisely the contention that
  produces these failures, and it invalidates both measurements").
- Session `0f2e8e05`, landing at the same minute (19:41), got a **spurious
  exit 6**: "suite RED in the primary tree after merging … Rolled back;
  worktree kept as evidence" — a good merge rolled back, plus ~4 min of
  investigation and a second land.

Fix direction: extend the existing lock to cover *any* `--all` run, not just
the land critical section.

- Reuse `<git-common-dir>/hone-land.lock` (one lock, so a land and an ad-hoc
  `--all` can never overlap) or add a sibling suite lock acquired by both.
- Acquisition points: `cmd_land`'s re-verify already holds it; add it around
  the gate's `--all` tier in `hooks/gate.sh` (short non-blocking wait — if the
  lock is held, block the stop with "another session is running the full
  suite; retry" rather than running red), and give the run skill a sanctioned
  wrapper (e.g. `worktree.sh verify`) for manual full-suite runs so agents
  stop invoking the adapter bare.
- The unit tier must stay lock-free — it is the per-Stop inner loop and cheap.

Acceptance: two concurrent runs each doing gate-`--all`/verify/land never
execute Chromium tiers simultaneously; a land never re-verifies while another
session's full suite is live; the unit tier is unaffected.

## 2. nag check 1 false-positives on every authored-but-unrun Plan

`hooks/nag.sh` check 1 treats "Plan with no worktree" as "landed or abandoned
without cleanup". But that state is also the *normal* plan→run gap — hone's own
model authors Plans first and runs them later, often from another session.

Field evidence: ~40+ firings across the window, almost all wrong. With six
Plans queued for parallel execution, every Stop injected six "delete it (git
keeps the history)" bullets against work that executed minutes later
(sessions `630729bb`, `b8a76740` — nag fired against Plans authored three
minutes earlier). Predictable alarm-fatigue result: the one genuinely stale
Plan (`session/live-policy-resolution`, landed weeks earlier) was ignored all
morning until the *human* noticed it (session `9a0df435`). The advice is also
actively dangerous if ever obeyed while runs are queued.

Fix direction: only flag a Plan when there is positive evidence its change
concluded, not mere absence of a worktree. Cheap signals available in the
primary tree:

- a landing merge commit in HEAD's history — `git log --grep
  "Merge branch 'hone/<change>'"` (land's fixed `-m` format makes this exact);
- or a surviving fully-merged `hone/<change>` branch (check 5 already computes
  this set — a Plan matching a check-5 finding is definitely stale).

No evidence → the Plan is pending; stay silent, or emit at most one aggregate
advisory line ("N Plans pending run") instead of per-Plan deletion advice.

Acceptance: fresh Plan + no worktree + no landed evidence → no finding; Plan
whose change has a `Merge branch 'hone/<change>'` commit in history → finding
fires as today.

## 3. Smaller items from the same logs

- **run skill: say where `.plans/` lives.** It exists (gitignored) only in the
  primary tree. Consolidate's `rm .plans/<change>.md` was attempted from the
  worktree and failed in two sessions (`1fee91a1`, `0f2e8e05`), the second
  spiraling into a "did I delete another session's work?" investigation when a
  parallel run had already emptied the directory. One sentence in
  `skills/run/SKILL.md`'s consolidate step (delete the Plan *from the primary
  tree*; tolerate it already being gone) removes the recurring stumble.
- **run skill: unattended runs shouldn't pause on review-findings scope.** One
  run stopped mid-loop to ask "apply all six findings, or land the narrow
  fix?" (session `a38978aa`), blocking until a human replied — against the
  run contract's premise. Give the loop a default: apply confirmed in-scope
  findings, note out-of-scope ones for a follow-up Plan, don't ask.
- **plan skill / plan-critic: ask the data-retention question before migration
  design.** A Plan with a schema migration went through six critic admission
  rounds and ~1.5 h of backfill design/empirics that all evaporated when the
  human said the existing data was disposable ("This is a test-deployment
  anyways.", session `181b95bd`). For any Plan touching a schema, require an
  explicit "is existing data worth preserving?" answer up front. Related: the
  critic at one point proposed hand-editing generated migration SQL, directly
  against the project's declared schema-management policy — the critic should
  read the project's migration policy before proposing migration mechanics.

Delete this file once the items are folded into Plans/issues.
