# Change under review: `notices/overdue-banner`

## Diff (consolidate step)

```diff
+++ b/src/notices/banner.ts
@@
+/** The banner a member sees while at least one loan is overdue. */
+export function overdueBanner(count: number, renewUrl: string): string {
+  const what = count === 1 ? "1 item is overdue" : `${count} items are overdue`
+  return `<p class="banner">${what}. <a href="${escapeAttr(renewUrl)}">Renew &amp; pay</a></p>`
+}
```

```diff
+++ b/src/notices/banner.test.ts
@@
+test("names one item in the singular", ...)
+test("escapes an ampersand in the renew url", ...)
+test("emits the banner markup byte for byte", ...)
```

```diff
+++ b/tests/browser/overdue-banner.test.ts
@@
+test("the banner reads 'Renew & pay' as one line of text", ...)
+test("the renew link opens the url the server sent, query string intact", ...)
```

```diff
+++ b/src/notices/page.ts
@@
-  const head = ""
+  const head = overdueBanner(overdue.length, renewUrl(member))
```

# Context

The Plan for this change is `notices/overdue-banner`. Consolidate deleted it.

Decisions touched: none. Notes touched: none. `docs/notes/notices.md` exists
and this change did not alter it.

`src/notices/banner.test.ts` asserts the string the server emits.
`tests/browser/` loads the page in a real browser. Its two assertions are
about what the browser's HTML parser makes of that string. One reads the
entity `&amp;` back as a single ampersand. The other checks that the `&`
inside the url's query string does not split the link. The two files run in
different tiers of the suite.
