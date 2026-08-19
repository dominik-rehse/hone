# Change under review: `queue/drain-on-shutdown`

## Diff (consolidate step)

```diff
+++ b/src/queue/shutdown.ts
@@
+/** Stop accepting work, then wait for in-flight jobs, up to `graceMs`. */
+export async function drain(q: Queue, graceMs: number): Promise<DrainResult> {
+  q.pause()
+  const finished = await q.awaitInFlight(graceMs)
+  return finished ? { ok: true } : { ok: false, abandoned: q.inFlight() }
+}
```

```diff
+++ b/src/queue/shutdown.test.ts
@@
+test("returns ok once every in-flight job finishes", ...)
+test("reports the abandoned jobs when the grace period expires first", ...)
+test("refuses new work as soon as drain starts", ...)
```

```diff
+++ b/docs/decisions/queue-shutdown.md
@@
+# Shutdown drains rather than kills
+
+On shutdown the queue stops accepting work and waits out the grace period,
+then reports what it abandoned. We rejected killing in-flight jobs: the
+billing consumer is not idempotent, so a killed job that already charged a
+card would charge it again on redelivery. The grace period is a caller
+argument rather than a constant because the web tier and the batch tier get
+very different shutdown windows from their platforms.
```

# Context

The Plan for this change is `queue/drain-on-shutdown`. Consolidate deleted it.

Notes touched: none. `docs/notes/queue.md` exists and this change did not
alter it.

The repository also holds this file, which the change does **not** touch:

`docs/spikes/2024-03-11-redis-vs-kafka.md`

```markdown
# Spike: can redis streams carry our queue, or do we need kafka?

**Date:** 2024-03-11 · **Status:** frozen. Written once, never maintained
against the code.

## Question
Redis streams or kafka for the job queue?

## What I did
Ran both under a 5k msg/s producer with one slow consumer, on the staging
box. The harnesses are beside this note, in
`docs/spikes/2024-03-11-redis-vs-kafka/`.

## Finding
Redis held 5k msg/s at a p99 of 40ms and blocked the producer at 10k pending
messages. Kafka held the same rate at a p99 of 90ms. Neither lost a message.
The deciding factor was not throughput: kafka needed a zookeeper ensemble we
had nobody to run.

## Where it landed
docs/decisions/queue-choice.md
```

`docs/decisions/queue-choice.md` exists and still records the redis choice.
The numbers in the note no longer match the current adapter. The queue has
since moved to redis 7. Its high-water mark is now 25k rather than 10k, and
nothing in `src/queue/` reports a p99 of 40ms any more.
