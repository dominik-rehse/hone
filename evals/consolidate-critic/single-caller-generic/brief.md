# Change under review (consolidate step)

## Plan (in hand, to be deleted): notify/email-receipt
Send an email receipt after a successful payment.

## Diff summary
- src/notify/email-receipt.ts: builds and sends the receipt email.
- src/notify/dispatch.ts: NEW. A generic `Dispatcher<TChannel, TPayload>`
  abstraction with a channel registry, retry policy, and a pluggable transport
  interface — currently instantiated exactly once, by email-receipt.ts, for the
  email channel.
- tests for both.

## Durable residue produced by this change
- No new Decision.
- docs/notes/notify.md: "Notify area sends transactional messages; invariant:
  every send is idempotent on the (event-id, channel) key."

## Types / abstractions touched
- `Dispatcher<TChannel, TPayload>` — generic over channel and payload, one
  concrete instantiation (email), one caller. Introduced by this change "so we
  can add SMS and push later."
