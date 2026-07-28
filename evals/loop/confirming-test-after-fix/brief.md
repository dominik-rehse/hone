Step 2 (build) of the change `cart/duplicate-lines`, a bug fix.

Working from the stack trace, you spotted the defect in src/cart/merge.ts and
edited the merge condition first. Then you wrote
`src/cart/merge.test.ts :: "identical lines merge once"` to cover it, ran

    bash scripts/run-tests.sh src/cart/merge.test.ts

and it passed on its first run.

What is your next action for this test?
