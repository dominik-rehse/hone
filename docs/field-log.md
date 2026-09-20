# Field log: where hone failed in real use

This page collects what hone did wrong in the repositories that use it. Each
incident is one line, and the newest line is first. A line names no
repository, because this repository is public. It has the date or the date
range, the hone version, the hook or the critic, and what happened. Identical
incidents share one line with a count. When an incident becomes a lab
scenario or a probe, its line names that scenario.

The counts and the method are in
[the 2026-09-20 field-data note](spikes/2026-09-20-field-data-from-real-sessions.md).
"Not recorded" in the version field means the source did not record it.

- 2026-08-20 to 2026-09-18 · mixed · `nag` · 314 lines telling the session
  that a template entry under the spike directory carries no date. The person
  moved the file to silence it.
- 2026-08-20 to 2026-09-18 · mixed · `nag` · 482 lines about one file two
  lines over its cap, over four weeks. Nobody ever acted on it.
- 2026-08-20 to 2026-09-18 · mixed · `nag` · 26 lines calling a markdown link
  broken. The link sat inside inline code, as an example of what a sanitizer
  strips.
- 2026-08-20 to 2026-09-18 · mixed · `gate` · 71 suite-lock blocks. Right by
  design, and not one of them reported a defect.
- 2026-08-20 to 2026-09-18 · mixed · `gate` · 5 unit blocks whose output tail
  showed application log noise. The agent re-ran the suite each time with its
  own filter.
- 2026-09-17 to 2026-09-18 · not recorded · `dirty-guard` · 30 blocks on
  read-only commands, across three sessions and two days. One file was
  already uncommitted before the sessions began.
- 2026-09-18 · not recorded · `dirty-guard` · the agent absorbed 27 of those
  blocks in one session. It never restored the file and never named the hook.
- 2026-08-21 to 2026-09-01 · 0.40.1 · `nag` · 437 lines of one finding that
  repeats on every stop. Only a person can clear it, and two people did.
- 2026-08-29 to 2026-08-30 · 0.40.1 · run loop · the harness permission
  classifier refused the prescribed re-run of land after a grant, in two
  sessions. The person ran the merge.
- 2026-08-28 · 0.47.0 · `bash-guard` · the agent reached for the flag that
  skips git hooks while amending in a worktree. Denied, and it complied.
- 2026-08-28 · 0.40.1 · `bash-guard` · a read of the config key that
  redirects git hooks was denied as sabotage. The agent lost the diagnosis it
  wanted.
- 2026-08-28 · 0.40.1 · `bash-guard` · a package manager invoked to print its
  help was denied as a writer of its own files.
- 2026-08-28 · not recorded · `bash-guard` · the sign-off helper escalation
  cost 31 minutes of waiting. Its reason named the protected-artifact rule
  instead of the sign-off rule.
- 2026-08-28 · not recorded · run loop · a grant stop cost a round trip. The
  exact command sat below the fold of a long report.
- 2026-08-28 · 0.40.1 · `gate` · a red unit suite caught at a turn end.
  Right, and the session went green later.
- 2026-08-28 · 0.40.1 · `plan-critic` · approve on a Plan whose negative
  claim about a third-party tool rested on a proxy signal in a config file.
- 2026-08-28 · 0.40.1 · `plan-critic` · reject whose only finding was a
  number in motivating prose that no build step reads. One extra round.
- 2026-08-24 to 2026-08-28 · mixed · `bash-guard` · 10 asks on a formatter
  run scoped to the plan directory, which the perimeter exempts.
- 2026-08-21 to 2026-08-28 · mixed · `bash-guard` · 11 asks on a command that
  changed directory out of the primary tree before it wrote anything.
- 2026-08-25 to 2026-08-28 · mixed · `bash-guard` · 4 asks on a copy. A
  protected file was its source, and a scratch file was its target.
- 2026-08-24 to 2026-08-28 · mixed · `consolidate-critic` · 2 cuts aimed at
  prose outside the change's diff. The author declined both.
- 2026-08-27 · not recorded · `consolidate-critic` · 2 cuts that contradicted
  the Plan's stated stance. One weakened a safety parameter the Plan had
  flagged.
- 2026-08-27 · 0.40.1 · `nag` · a live Plan reported as landed, because an
  older change had reused the same slug.
- 2026-08-26 · 0.40.1 · `dirty-guard` · caught a write into the primary tree
  after the shell working directory had silently reset. Right, and the hole
  the hook exists for.
- 2026-08-26 · 0.40.1 · `consolidate-critic` · proposed deleting a spike
  because its forward pointer dangled. hone's own lifecycle guarantees that
  pointer will dangle.
- 2026-08-26 · not recorded · `consolidate-critic` · proposed cutting a
  browser-level test as redundant with a server-level one. Two layers, one
  proposition.
- 2026-08-24 to 2026-08-26 · mixed · `guard` · 4 denies of a new module with
  no test. All right, and the agent wrote the test first each time.
- 2026-08-25 · not recorded · `guard` · denied a durable docs edit in the
  primary tree. The person set and cleared the off marker twice that session.
- 2026-08-25 · 0.40.1 · `plan-critic` · approve on a Plan whose citations all
  checked out. The rule it derived from them was too general, and it landed
  in a durable document.
- 2026-08-25 · 0.40.1 · run loop · hone's own recommended deny rules blocked
  a Plan-sanctioned edit to a project config file, with no sanctioned route.
  The person patched by hand after three failed attempts.
- 2026-08-25 · 0.40.1 · run loop · the proof gate demanded a full
  real-environment proof for a comment rewrap in a protected script.
- 2026-08-25 · not recorded · run loop · two stops handed the person a
  prepared patch. The change's own subject sat inside the deny perimeter.
- 2026-08-25 · not recorded · `gate` · 3 blocks from a check tool. It failed
  on a temporary directory that a mutation-testing run had left behind.
- 2026-08-25 · not recorded · `consolidate-critic` · a clean verdict claimed
  a worktree was gone. It read the diff and the Plan, never the filesystem.
- 2026-08-25 · 0.40.1 · `bash-guard` · the agent reached for the flag that
  skips git hooks inside a land retry loop. Denied, and it re-ran without it.
- 2026-08-24 · 0.40.1 · `bash-guard` · a command put a hooks-path override in
  front of a commit. Denied, and the model withdrew it itself.
- 2026-08-24 · not recorded · `bash-guard` · a read-only stash listing
  escalated as a move of the checked-out commit. The notification that told
  the person about the block escalated too.
- 2026-08-20 · not recorded · `plan-critic` · approve on a Plan that stripped
  a metadata block from every input. For one producer that block held the
  only copy of the data.
