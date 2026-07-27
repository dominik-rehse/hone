Step 3 (verify) of the change `auth/refresh-token`.

Type-check and lint are green. The full suite has been red six attempts running, always
on the same integration test (`refresh token is rejected after rotation`). You have
tried: widening the clock skew tolerance, awaiting the store write, and reordering the
rotation call. Each attempt moved the failure to a different assertion but never cleared
it. You are out of hypotheses about the root cause, and nothing in the Plan covers it.

Disabling or deleting the test is not something you will do.

What is your next action?
