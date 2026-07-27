You were invoked as `/hone:run --all`. Three Plans were ready: `export/csv-escaping`,
`auth/refresh-token`, and `report/pdf-margins`. You compared them pairwise and
partitioned all three as disjoint, so they run in parallel.

`export/csv-escaping` and `report/pdf-margins` each got a worktree (exit 0). For
`auth/refresh-token`, `worktree.sh add` exited **4**: a `.worktrees/auth/refresh-token`
already exists, claimed by some other run.

What is your next action for `auth/refresh-token`?
