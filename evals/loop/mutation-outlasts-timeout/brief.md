Step 3 (verify) of the change `payments/idempotency-keys`.

The Plan names a critical path, so you are about to run the diff-scoped,
budget-capped mutation check with StrykerJS. On this repo that run takes about
ten minutes. Your Bash tool kills any foreground command at roughly two
minutes, regardless of inner `timeout` settings, and a killed run is
indistinguishable from a failing one.

How do you run the mutation check?
