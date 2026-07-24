# Change under review (garden maintenance pass, repo-wide)

## Plan
None — this is a /hone:garden continuous-maintenance run, not a feature change.
The candidate cut below was surfaced by a repo-wide drift scan.

## Candidate cut
- docs/decisions/legacy-sync.md (Governs: src/sync/poller.ts):

  > # Legacy sync
  > We poll the vendor API every 30s from a background poller and reconcile
  > deltas into the local store. Polling (not webhooks) because the vendor had no
  > webhook support at integration time.
  > Rejected: webhooks — unavailable then.

## Repo evidence the scan collected
- src/sync/poller.ts was deleted three changes ago; the whole src/sync/ area is
  gone. `grep -r poller src/` returns nothing.
- The vendor integration now lives in src/webhooks/ and is webhook-driven; a
  newer docs/decisions/vendor-webhooks.md records that choice and its why.
- docs/decisions/legacy-sync.md still sits in the tree, Governs: a path that no
  longer exists.

## Types / abstractions touched
- none.
