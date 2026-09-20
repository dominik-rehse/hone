Review the change below.

## Plan: scheduler/per-tenant-quota

### What
Add `src/quota.js`. It counts, per tenant, the jobs that went in since the
window opened. It carries `count`, `record`, `remaining`, `resetWindow`,
`windowIsOver`, and a `startWindows` that opens a new window every minute.
Give `src/tenants.js` a
plan table, with `limitFor` and `priorityFor` to read it. Have `submit` in
`src/scheduler.js` turn a tenant over its limit away with `over-quota`. Have it
stamp the plan's priority on the job it makes. Have `nextBatch` in
`src/dispatch.js` hand out the steepest plan first, and add an `upNext(n)` the
status endpoint can read. Add `remaining(tenantId)` to the scheduler, and put
the counts on the status.

### Why
A tenant on the free plan posted eleven thousand report jobs one morning last
week. The queue filled up. The workers spent four hours on that one tenant,
and everybody else waited. Support had nothing to turn it off with.

### How I'll know it works
A free tenant's sixth job in a window comes back `over-quota`, with the limit
it ran into. A tenant on the paid plan goes a long way further. A new window
lets a tenant that ran out put jobs in again. A job carries the priority its
plan buys. Two jobs on one plan come off the queue in the order they arrived.
The status endpoint reads the counts per tenant. `upNext` reads what is
waiting without taking anything off.

### Notes for the loop
- The counts live in memory beside the queue. A restart opens a new window.
- A plan the table does not carry reads as free.
- The old webhook keeps the path it has. Its two customers sit on a contract
  that came before the plans, and a later change brings them over.
- The window is a minute long. Nothing here sits on a hot path.
