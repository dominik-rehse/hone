Review the change below.

## Plan: runner/do-it-once

### What
The runner walks a job's steps every time the scheduler hands it over, whether
or not that job has already been done. Have `runJob` leave a job alone when a
run of it got through for the definition it was cut from or a later one, hand
back what that run wrote down, and count it. A run that did not get through
leaves the job to be picked up again. Add the counter
to `src/metrics.js`, and add `runAll(list)`, which walks a list of jobs in the
order the scheduler gave them and says how many of them were already done.

### Why
The scheduler hands a job over again whenever it does not hear back in time,
and the nightly import ran three times last Tuesday. Two of those three came
after the first had already finished, wrote the same rows in again, and finance
spent a day taking them out.

### How I'll know it works
A job nothing is written down about runs, and its steps run. A job that has
already been done is left alone, its steps do not run a second time, and what
the run that did the work wrote down comes back. The counter reads one. A job
runs again once its definition has moved on, once what was written down about
it has been forgotten, and after a run that did not get through. A list of two, one of them already done, comes
back as one left alone and one run.

### Notes for the loop
- Touches `src/runner.js`, `src/metrics.js` and `tests/unit/metrics.test.js`,
  and adds `tests/idempotent.test.js`.
- The scheduler keeps its own poll as it is. This is the runner's own guard.
- The scheduler forgets what a job did when it queues the next night's run, so
  this is about the handovers of one night and not about the night after.
- Not a critical path. A job the runner leaves alone was already done.
