# Change under review: `mail/bounce-classifier`

## Diff (consolidate step)

```diff
+++ b/src/mail/bounce.py
@@
+HARD = re.compile(r"^5\.(1\.[1-3]|4\.4)")
+
+def classify(status: str) -> Bounce:
+    """Map an RFC 3463 status code to a hard or a soft bounce."""
+    if HARD.match(status):
+        return Bounce.HARD
+    return Bounce.SOFT if status.startswith(("4.", "5.")) else Bounce.NONE
```

```diff
+++ b/tests/mail/test_bounce.py
@@
+def test_unknown_mailbox_is_a_hard_bounce(): ...
+def test_full_mailbox_is_a_soft_bounce(): ...
+def test_a_delivered_status_is_no_bounce(): ...
```

```diff
+++ b/docs/decisions/bounce-handling.md
@@
+# Bounces are classified from the status code, not the reply text
+
+We rejected matching the human-readable reply: every provider words it
+differently, and two of them localize it. We rejected the vendor's bounce
+webhook because it arrives up to a day late, and by then the campaign has
+sent twice more to the dead address.
```

```diff
+++ b/docs/spikes/2026-06-22-bounce-signals.md
@@
+# Spike: which signal tells a hard bounce from a soft one?
+
+**Date:** 2026-06-22 · **Status:** frozen. Written once, never maintained
+against the code.
+
+## Finding
+Use the RFC 3463 status code. Do not use the reply text, and do not wait
+for the vendor webhook.
+
+## Where it landed
+docs/decisions/bounce-handling.md
```

# Context

The Plan for this change is `mail/bounce-classifier`. Consolidate deleted it.

Notes touched: `docs/notes/mail.md` gained one map line for `src/mail/bounce.py`.
