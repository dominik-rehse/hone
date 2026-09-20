# Change under review: `parser/clock-skew-tolerance`

## Diff (consolidate step)

```diff
+++ b/src/parser/timestamp.ts
@@
-  if (at > now) throw new SkewError(at)
+  if (at > now + TOLERANCE_MS) throw new SkewError(at)
```

```diff
+++ b/src/parser/timestamp.test.ts
@@
+test("accepts a reading two seconds ahead of the reader's clock", ...)
+test("still rejects a reading an hour ahead", ...)
+test("names the offending timestamp in the error", ...)
```

```diff
+++ b/docs/decisions/clock-skew.md
@@
+# The parser tolerates a small forward skew
+
+We rejected trusting the device clock: a device without a battery-backed
+clock reports 1970 after a power cut, and the whole file would then be
+accepted. We rejected syncing the fleet, because half of it sits on a
+metered link the owner will not pay more for. A fixed forward tolerance is
+what the field data supports.
```

```diff
+++ b/docs/spikes/2026-04-18-clock-skew.md
@@
+# Spike: how far ahead of us do the devices run?
+
+**Date:** 2026-04-18 · **Status:** frozen. Written once, never maintained
+against the code.
+
+## What I did
+Collected the first timestamp of every upload over nine days, against the
+reader's own clock. The script sits beside this note, in
+`docs/spikes/2026-04-18-clock-skew/`.
+
+## Finding
+Of 4,100 uploads, 61 ran ahead of the reader. The largest lead was 1.4
+seconds, and three devices account for 58 of the 61. A tolerance under one
+second would still reject those three. Rounding the reader's clock down to
+the second was the first idea, and it moved 9 of the 61.
+
+## Where it landed
+`docs/decisions/clock-skew.md`, and the Plan
+`.plans/parser/clock-skew-tolerance.md`.
```

# Context

The Plan for this change is `parser/clock-skew-tolerance`. Consolidate deleted
it, so `.plans/parser/clock-skew-tolerance.md` no longer exists.

Notes touched: none. `docs/notes/parser.md` exists and this change did not
alter it. `docs/decisions/clock-skew.md` is new in this change.
