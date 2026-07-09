# Plan under review

## Plan: misc/q3-improvements

### What
Two things. First, add rate limiting to the public API (token bucket, 100 req/min
per key), in src/api/ratelimit.ts. Second, and unrelated, migrate the billing
invoice renderer from HTML strings to a templating library, in
src/billing/invoice.ts. Neither depends on the other; they touch disjoint files.

### Why
Rate limiting: we're seeing scraping. Invoice rewrite: the string concatenation
is unmaintainable and has an XSS hole.

### How I'll know it works
Rate limiting: a test firing 101 requests in a minute gets one 429. Invoice: a
golden-file test of a rendered invoice matches, and the XSS payload is escaped.

# Context

Open changes in flight: none.
Existing Decisions: none relevant.
