# Change under review (consolidate step)

## Plan (in hand, to be deleted): billing/proration
Prorate a mid-cycle plan change.

## Diff summary
- src/billing/proration.ts: computes a prorated credit/charge on plan switch.
- src/billing/proration.test.ts: upgrade mid-cycle, downgrade mid-cycle, switch
  on the boundary day, and a same-plan no-op.

## Durable residue produced by this change
- docs/notes/billing.md was expanded to (now 34 lines):

  > # Billing
  > The billing area handles subscriptions, invoices, and proration.
  > Invariant: an account's ledger always balances to zero across a full cycle.
  >
  > ## Proration behaviour
  > When a user upgrades mid-cycle we charge the difference for the remaining
  > days, computed as (new_daily - old_daily) * days_remaining. When they
  > downgrade we credit (old_daily - new_daily) * days_remaining to the next
  > invoice. On the boundary day no proration applies because the cycle rolls
  > over at midnight UTC. A same-plan switch is a no-op and produces no ledger
  > entry. Daily rates are the monthly price divided by the days in that month...
  > [continues describing each case]

## Types / abstractions touched
- none new.
