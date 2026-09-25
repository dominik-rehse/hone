# Field log: where hone failed in real use

This page collects what hone did wrong in the repositories that use it. Each
incident is one line, and the newest line is first. A line names no
repository, because this repository is public. It has the date or the date
range, the hone version, the hook or the critic, and what happened. Identical
incidents share one line with a count. When an incident becomes a lab
scenario, a probe, or an eval case, its line names it. A case path is below
`evals/`.

The counts and the method are in
[the 2026-09-20 field-data note](spikes/2026-09-20-field-data-from-real-sessions.md)
and [the 2026-09-25 field-data note](spikes/2026-09-25-field-data-since-0-58.md).
"Not recorded" in the version field means the source did not record it.

- 2026-09-25 · 0.59.1 · `garden` · `skills/garden/SKILL.md` reads every land
  exit 6 as "the cut was unsafe," but since 0.59.1 a refused merge hook also
  exits 6. Fixed in 0.61.0.
- 2026-09-25 · 0.59.0 · `plan-critic`/`consolidate-critic` · both missed
  that a CLI upgrade had made a stated Decision false. The nested review
  caught it instead.
- 2026-09-25 · mixed · `gate` · exit 9 reported a refused pre-merge-commit
  hook as a merge conflict, in three sessions. Fixed in 0.59.1.
- 2026-09-25 · 0.58.1 · `nag` · a "survived its landing" false alarm fired
  three times in one session. This happened while its worktree was still
  legitimately open, right after a rollback. Fixed in 0.62.0.
- 2026-09-25 · 0.58.1 · `dirty-guard` · blamed paths from another session's
  half-finished manual merge in the primary tree on two unrelated commands.
  Both agents correctly declined the hook's suggested restore. Fixed in 0.62.0, reverted in 0.62.1 after a review found shapes it let through. Open.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `gate` · post-merge checks in the
  primary tree read other sessions' untracked draft Plans, causing at
  least 6 spurious rollbacks. Fixed in 0.60.0.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `bash-guard` · a scratch
  `stryker.conf.json` for the mutation check matched the tracked-check-
  config rule. The ask did not name the file. Unattended runs stalled 7
  hours, 81 minutes, 69 and 12 minutes, and 40 minutes across four
  sessions. Fixed in 0.62.0, reverted in 0.62.1 after a review found shapes it let through. Open.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `bash-guard` · the primary-branch-
  move ask fired 14 times, 3 right and 11 false. False shapes: a
  directory change into a scratch worktree, a path-scoped `git reset`,
  and a checkout addressed only by a shell variable. One false ask sat
  40 minutes. Fixed in 0.62.0, reverted in 0.62.1 after a review found shapes it let through. Open.
- 2026-09-21 to 2026-09-25 · mixed · `bash-guard` · denied a formatter run
  as writing a durable file, three times. Its target path was an
  unresolved variable. It also denied a read-only listing under
  `.hone-grant/triggers/` as a write into it. It denied a package-manager
  init or install in a scratchpad or worktree as writing its own files,
  four times. Fixed in 0.62.0, reverted in 0.62.1 after a review found
  shapes it let through. Open.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `gate` · the suite-lock block named
  "another session" as the holder, about 20 times. The real holder was
  the session's own land, or its background verify. The block skips the
  retry cap, so an agent looped on turns with no visible output. Fixed in 0.62.0.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `nag` · the broken-link check read
  `javascript:` and `data:` links inside inline code as real. It printed
  on every stop in every session. A doc over its line cap and a list of
  pending Plans also repeated on every stop, with no action taken. Fixed in 0.62.0.
- 2026-09-21 to 2026-09-25 · mixed · run loop · 10 of 23 finished runs
  printed fewer than 5 of the 6 step-start progress lines.
  `skills/run/SKILL.md` asks for one at the start and end of each step.
  Five runs went quiet for 30 to 50 minutes with no line at all.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `plan-critic` · approved a Plan
  whose Proof trailer needed a probe script keyed by the change's slug.
  No such script existed. This happened twice, and land then failed the
  proof gate both times. Fixed in 0.61.0: the critic checks the proof
  route.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `consolidate-critic` · proposed
  three cuts a person had to decline. They were: a required
  `MutationObserver`, a test and a sentence nested review later restored,
  and content outside the diff that another Plan had ring-fenced.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `plan-critic`/`consolidate-critic` ·
  verdict format drifted: a bolded verdict, a "Verdict:" prefix, prose
  after the verdict, a file list last. Clean on a small 0.59.0 sample,
  too small to call fixed.
- 2026-09-21 to 2026-09-25 · 0.58.1 · `gate` · the authority gate (exit 8)
  fired 3 times and caught nothing real. Twice it fired on SQLite's
  table-rewrite idiom, and once as a false alarm from the land rollback
  bug below. Partly addressed in 0.60.0: the refusal now quotes each
  destructive statement with its file.
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · land run from inside its
  own worktree exited 2 after a successful merge, three times. It also
  printed getcwd noise. `worktree.sh remove` also rejected a change name
  or a relative path, twice. Fixed in 0.60.0.
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · a Sonnet main session
  retried land blindly after an exit 9 or exit 6, twice. Once this went
  against `land.md`'s own "stop and escalate," citing a memory file
  instead. The run skill forbids it since 0.61.0.
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · `/hone:plan` fired when
  the person had asked for a chat handoff instead ("No, don't plan").
  Addressed in 0.61.0: the plan skill fires only for a Plan.
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · a session created and
  landed an unplanned worktree after the person said "You do it."
- 2026-09-21 to 2026-09-25 · 0.58.1 · run loop · the person twice asked
  the agent to speak plainly. Once was about a plan-skill blocking
  question, once about a run reply.
- 2026-09-22 · 0.58.1 · run loop · land's rollback `git reset --hard`
  dropped a concurrent Plan's own commit from main, twice. A branch cut
  from the dropped commit later caused a false exit 8. Fixed in 0.60.0.
- not recorded · 0.58.1 · run loop · land's receipt named the wrong
  commit as the merge. It named a Plan commit made mid-suite, not the
  real merge. Fixed in 0.60.0.
- not recorded · 0.58.1 · `plan-critic` · took four rounds, about 17
  minutes, on a one-paragraph docs Plan. Each reject named a real
  contradiction, mostly introduced by the previous fix.
- not recorded · 0.58.1 · `gate` · the proof gate named a probe script
  for a change that had edited another change's probe. That script did
  not exist. Fixed in 0.60.0.
- 2026-09-21 · 0.58.1 · `session-start` · one session's workflow-rule
  injection went missing. Right by design: the person had created the off
  marker ten seconds before that session started.

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
  Case: `plan-critic/tool-negative-from-config`.
- 2026-08-28 · 0.40.1 · `plan-critic` · reject whose only finding was a
  number in motivating prose that no build step reads. One extra round.
  Case: `optimize/cases/plan-critic/stale-count-in-motive`.
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
  Case:
  `optimize/cases/consolidate-critic/spike-pointer-to-deleted-plan`.
- 2026-08-26 · not recorded · `consolidate-critic` · proposed cutting a
  browser-level test as redundant with a server-level one. Two layers, one
  proposition.
  Case: `consolidate-critic/same-claim-two-layers`.
- 2026-08-24 to 2026-08-26 · mixed · `guard` · 4 denies of a new module with
  no test. All right, and the agent wrote the test first each time.
- 2026-08-25 · not recorded · `guard` · denied a durable docs edit in the
  primary tree. The person set and cleared the off marker twice that session.
- 2026-08-25 · 0.40.1 · `plan-critic` · approve on a Plan whose citations all
  checked out. The rule it derived from them was too general, and it landed
  in a durable document.
  Case: `plan-critic/invariant-overgeneralised`.
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
  Case: `consolidate-critic/ordered-deletion-not-in-diff`.
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
  Case: `plan-critic/indexer-strips-only-copy`.
