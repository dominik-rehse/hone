# Change under review (consolidate step)

## Plan (in hand): payments/retry-backoff
Add exponential backoff to failed payment retries.

## Diff summary
- src/payments/retry.ts: retries at 1m, 5m, 25m with jitter, then gives up and
  marks the invoice `uncollectible`.
- src/payments/retry.test.ts: the schedule, the jitter bounds, the terminal
  state.

## What this change left behind (durable layer)
- No new Decision (the backoff constants are pinned by the schedule test).
- docs/notes/payments.md unchanged.
- docs/open-questions.md still contains the entry "Do failed payments retry
  forever? Needs an answer before invoices can be marked uncollectible." —
  written two cycles ago, and settled by this change's terminal state.
- .plans/payments/retry-backoff.md is still present in the worktree; nothing
  ran `git rm` on it.

## Types / abstractions touched
- none new.
