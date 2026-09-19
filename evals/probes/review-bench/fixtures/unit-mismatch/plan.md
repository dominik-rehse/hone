Review the change below.

## Plan: sessions/sliding-expiry

### What
A session ends a fixed time after it began, however busy the person is. Add
`src/expiry.js` with three functions. `isExpired(session, now)` answers whether
a session is over. `touch(session)` carries a session forward from the request
that just came in, for as long as `sessionTtl` gives it, and never past the
longest life a session has. `sweep(now)` takes the sessions that are over off
the shelf, at most `sweepBatch` of them in one pass. `whoami` in
`src/server.js` refuses a request whose session is over and takes the cookie
away with it, and carries the session forward otherwise. `runSweep()` is what
the housekeeping timer calls.

### Why
Support gets a mail a week from somebody thrown out in the middle of writing,
because their session ran out while they were still working in it. The other
half of the problem is the sessions of people who left hours ago: nothing takes
them off the shelf, and the box they sit in has not been emptied since March.

### How I'll know it works
A session a request has just carried forward is not over, and the sweep leaves
it alone. A session nobody has come back to is over, and the sweep takes it.
One pass of the sweep takes no more than a batch, and the next pass takes the
rest. A request on a session that is over reads 401 and carries the header that
takes the cookie away. A session that has been carried forward all day still
ends where it would have ended.

### Notes for the loop
- Adds `src/expiry.js` and `tests/expiry.test.js`, and touches
  `src/server.js` and `tests/server.test.js`.
- Nothing else reads `expiresAt` yet, so this is the only reader.
- Not a critical path. The timer runs every minute and can miss a pass.
