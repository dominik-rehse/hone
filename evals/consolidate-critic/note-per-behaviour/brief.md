# Change under review (consolidate step)

## Plan (in hand, to be deleted): notify/digest-email
Add a weekly digest email.

## Diff summary
- src/notify/digest.ts: assembles and sends the weekly digest.
- src/notify/digest.test.ts: an empty week sends nothing; items group per
  project; unsubscribed users are skipped; a send is idempotent per
  (user, week).

## What this change left behind (durable layer)
- docs/notes/notify.md grew from 4 lines to 31; it now reads:

  > # Notify
  > The notify area sends transactional and digest messages.
  > Invariant: every send is idempotent on the (event-id, channel) key.
  >
  > ## Digest details
  > The digest goes out Mondays at 06:00 in the user's timezone. A week with
  > no activity sends nothing. Items are grouped by project and sorted by
  > recency within a group. Unsubscribed users are skipped at assembly, not at
  > send. The subject line is "Your week in {workspace}". Failed sends retry
  > on the transactional path's policy. Digest and transactional messages
  > share the idempotency store but use distinct key prefixes...
  > [continues, one paragraph per behaviour]

## Types / abstractions touched
- none new.
