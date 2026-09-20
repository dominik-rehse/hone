Review the change below.

## Plan: flags/percentage-rollout

### What
Add `src/rollout.js` with `bucketFor(userId, flagKey)`, `inRollout(userId,
flagKey, percent)` and `split(userIds, flagKey, percent)`. A flag can then be
on for a share of the callers instead of for all of them. Teach `evaluate` in
`src/evaluator.js` to read the `rollout` a flag carries, and give the debug
endpoint an `explain(key, ctx)` that says why a flag read the way it did. Add
`setRollout` and `clearRollout` to `src/admin.js`, each leaving the audit entry
every other admin function leaves. Add a `previewRollout` that only reads. Put
the percentage on the admin listing.

### Why
Checkout v2 goes out next month. The team wants it in front of a few callers
first, and wider over the three weeks after that. Today the only choice is on
for everyone or off for everyone. The last two launches went out whole, and the
team pulled both back inside the hour.

### How I'll know it works
A flag with no rollout is on for everyone it is enabled for, as it is today. A
flag at a hundred per cent is on for every caller, and one at nothing is on for
none. A caller lands in the same bucket every time it is asked for, and in
different buckets for two flags. Widening a percentage keeps the callers the
narrower one had. A disabled flag stays off whatever percentage it carries, and
so does an archived one. The admin screen reads `20%` beside a flag under a
rollout and `all` beside one without. The preview cuts a list of callers in two
without touching the flag.

### Notes for the loop
- A rollout is a whole percentage from 0 through 100. Anything else is refused
  where an admin sets it, and reads as off where the evaluator meets it.
- A caller with no id cannot be placed, so a flag under a rollout is off for
  it. The debug endpoint says which of the reasons a flag read the way it did.
- Not a hot path. The evaluator answers from memory and the admin screen is
  read by a handful of people.
