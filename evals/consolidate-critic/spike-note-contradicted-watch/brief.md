# Change under review: `queue/raise-high-water-mark`

## Diff (consolidate step)

```diff
+++ b/src/queue/backpressure.ts
@@
-export const HIGH_WATER_MARK = 10_000
+export const HIGH_WATER_MARK = 25_000
```

```diff
+++ b/src/queue/backpressure.test.ts
@@
-test("blocks the producer at 10k pending messages", ...)
+test("blocks the producer at 25k pending messages", ...)
+test("accepts a burst of 20k without blocking", ...)
```

```diff
+++ b/docs/decisions/queue-backpressure.md
@@
+# The producer blocks at 25k pending messages
+
+We raised the mark from 10k because the nightly import bursts to 18k and
+blocked itself for forty minutes every night. We rejected removing the mark:
+an unbounded stream took the redis host down in the 2025 incident. 25k is
+the largest burst of last quarter plus a third, and it fits in the memory
+the redis 7 host has free at peak.
```

# Context

The Plan for this change is `queue/raise-high-water-mark`. Consolidate deleted
it.

Notes touched: none. `docs/notes/queue.md` names `backpressure.ts` in its map
and states no number.

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
After this change the note's "blocked the producer at 10k pending messages"
is no longer what the queue does.
