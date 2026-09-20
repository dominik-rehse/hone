# Spike: what hone did in 220 real sessions

**Date:** 2026-09-20 · **Status:** frozen. Written once, never maintained
against the code.

## Question

[`field-log.md`](../field-log.md) was empty, and step 5 of the handoff needs
a table: per hook, how often it fired, and whether each block was right. The
handoff also asks for the real misjudgments of the two critics. This note
holds both.

## Method

I read the Claude Code session transcripts of four private consumer
repositories. They are one person's work. Nothing here says how hone behaves
for a second user or on another language stack.

The corpus splits into two groups, because the hone versions differ.

| group | repositories | sessions | hone versions | dates |
| --- | --- | --- | --- | --- |
| A | 1 | 134 | 0.1.0 to 0.47.0 | 2026-08-20 to 09-18 |
| B | 3 | 86 | 0.40.1 | 2026-08-21 to 09-01 |

Coverage. In group A, 94 of 134 sessions name the plugin, and a hook printed
or blocked in 97. The rest are short sessions, plan-only sessions, and early
sessions with a smaller hook set. In group B, all 86 sessions carry the
injected workflow rule, and 77 produced at least one hook event.

Detection in group B reads the structured hook records of the harness, so its
per-hook counts are complete for that corpus. Group A deduplicates on four
fields: the session file, the line, the hook, and the kind. It has to,
because the harness stores a hook's text in more than one place. Every count
below is a lower bound, not an exact firing count.

The judgment of a critic verdict is weaker than the judgment of a hook block.
A Plan that was approved and simply worked leaves no trace of a near miss.
So the misjudgment count is a lower bound too.

## The hook table

"Fired" counts a deny, an ask, a block, or an advisory. A silent allow is not
counted. The `nag` row counts advisory lines, not messages.

| hook | fired A | fired B | fired | right | false alarm | unclear |
| --- | --- | --- | --- | --- | --- | --- |
| `guard` | 3 | 2 | 5 | 5 | 0 | 0 |
| `bash-guard` | 16 | 34 | 50 | 19 | 28 | 3 |
| `dirty-guard` | 44 | 1 | 45 | 4 | 41 | 0 |
| `gate` | 91 | 1 | 92 | 89 | 3 | 0 |
| `nag` | 1517 | 693 | 2210 | 1382 | 342 | 486 |
| `session-start` | 0 | 0 | 0 | 0 | 0 | 0 |

The `nag` unclear column is the advisory-by-design lines, which are never
actionable. The two groups classified those differently. Group A put 486 such
lines in the unclear column. Group B counted its 85 in the right column, so
the right column of the `nag` row is generous by that much.

Of the 91 `gate` blocks in group A, 71 are the suite lock, which is right by
design. The other 20 are real check failures, 17 right and 3 false.

### Denominators

- The Stop hook ran 216 times in group B. It blocked once. It printed a green
  line 21 times. The other runs were no-ops on a clean tree or a non-hone
  branch. In real use the Stop gate almost never engages, because the loop
  commits in a worktree and stops when the tree is clean.
- `session-start` ran 345 times in group B and printed no setup warning.
  Every repository had its adapters and its source directory.
- The `nag` fired on 208 of those 216 stops.
- 276 critic runs in all. `plan-critic` ran 140 times: 114 approve, 17 reject,
  and 9 whose verdict was not on the last line. `consolidate-critic` ran 136
  times: 95 with cuts, 31 clean, and 10 with no verdict on the last line.

## Shapes of the false alarms

Each shape is stated in general terms. Where the check was cheap I read the
current hook code and say what holds today.

### `guard`

None. All five blocks were right, and the agent complied each time.

### `bash-guard`

1. The command changes directory into a worktree first, and the guard still
   judges it against the primary tree. Fixed since. The hook now reads the
   shell's own directory, and a leading change of directory, including one
   inside a subshell.
2. The command changes directory into a scratch directory outside any git
   repository. The tree test compares two empty answers and reads that
   directory as the primary tree. Still present in the code of today. The
   same holds when the target is a shell variable the hook cannot resolve.
3. A read-only git verb reads as a move of the checked-out commit. Fixed
   since for the two reading forms of the stash verb. Still present for a
   file restore written without the path separator, which the code names as
   a known residual.
4. A formatter run scoped to the plan directory still asks, although the
   perimeter exempts that directory. Fixed since. A scoped formatter run now
   passes, and the rule has its own message.
5. A protected file is the source of a copy, and the write lands in a scratch
   file. The rule reads a protected path anywhere in the command, not the
   direction of the write. Still present in the code of today.
6. A token matches inside a quoted string that the agent wrote to tell the
   person about an earlier block. Partly fixed. A commit message and a
   sign-off text are stripped before the rules read the command. Any other
   quoted string is still read, so a formatter name inside a notification
   body still asks. Still present in the code of today.
7. A read of the config key that redirects git hooks is denied as sabotage.
   The hook's own header says that a read is legitimate. Still present in the
   code of today.
8. A package manager invoked only to print its help. A bare help call now
   passes. Still present when any further token follows the flag.
9. The deny reason for the sign-off helper named the protected-artifact rule
   instead of the sign-off rule. Fixed since. That helper has its own rule
   and its own message.

Shapes 1, 3, and 4 account for most of group A's noise. Shapes 2, 5, 6, and 7
account for most of group B's.

### `dirty-guard`

1. The hook reports the tree's dirty durable paths, not the effect of the
   command. One file left uncommitted therefore blocks every later shell
   command in the session, including pure reads. In group A one stale file
   produced 30 blocks across three sessions and two days. Still present in
   the code of today, by design: the hook reads the tree and never the
   command.
2. The block names a file that a person edited by hand. The restore command
   the message offers would then destroy that person's uncommitted work.
   Still present in the code of today.

In the largest cluster the agent absorbed 27 blocking messages, never
restored the file, never moved to a worktree, and never mentioned the hook.
That is alarm fatigue in its clearest form.

### `gate`

1. A check tool fails on a temporary directory that a mutation-testing run
   left inside the worktree. The change did not cause it. This is the
   project's tool configuration, not hone's code. Not checked.

One message defect is not a false alarm but costs a round trip every time.
The block prints the last fifteen lines of the adapter's output. For a test
runner those lines are application log noise, so the agent re-runs the suite
with its own filter to learn what broke. Five such cases in group A. Still
present in the code of today.

The suite lock blocked 71 turn ends in group A and never reported a defect.
It is the price of running several worktrees at once against one machine.

### `nag`

1. A template entry under the spike directory carries no date at the front of
   its name, and the check reads it as an undated spike. Still present in the
   code of today. The rule checks every top-level entry with no exemption for
   a name that starts with an underscore.
2. The link checker reads a markdown link inside inline code as a real link.
   Still present in the code of today. The check greps the whole file.
3. A Plan is reported as having survived its landing, because an older change
   reused the same slug. The check looks for a merge commit by branch name.
   Still present in the code of today.
4. A Plan is reported as landed although its branch carried no commit of its
   own. Fixed since. The check now requires the branch tip to sit off the
   first-parent line of the primary branch.

Two `nag` findings are right every time and repeat on every stop until a
person acts by hand. One of them was 63 percent of everything the `nag` said
in group B. The other named one file two lines over its cap, and printed 482
times over four weeks in group A with no action taken.

## Sabotage, and the off marker

Three reaches in 220 sessions. Each was denied, and the model complied on
first contact.

| what was reached for | count | group |
| --- | --- | --- |
| the flag that skips git hooks, in front of a commit | 2 | A |
| the config key that redirects git hooks, in front of a commit | 1 | B |

Both reaches in group A had the same motive. The agent wanted past its own
formatting churn, not past a failing check. In both cases it removed the flag
and re-ran the identical command. In group B the model read the block and
wrote that it had no business including the token.

No file tool ever aimed at a protected path in a way the deny rules had not
already stopped. No agent ever created the off marker, and no agent asked for
one outside the single case where a guard told it to.

The off marker was used twice, in one session of group A. A person set it
both times and removed it both times. Each use was a durable docs edit in the
primary tree that was not worth a worktree. The two windows were about 35
minutes and about 2 minutes. Both commits record the marker in their body.
Group B has zero uses in 86 sessions.

One hazard is on record. A concurrent land hard-resets the primary tree, and
an edit made under the marker is the common casualty.

## Human attention

- 43 sessions in group B began with the run command. 30 of them needed zero
  human turns after the invocation. The other 13 are listed below.
- Group A had 60 run sessions and 83 turn ends.

Stops that were due:

- The proof gate, exit 7: 20 in group A, 10 in group B. The agent refused to
  sign off on a check it could not run. One report says that a sign-off
  naming a check nobody ran is worse than no gate.
- The authority gate, exit 8: 10 in group A, 12 in group B. In group B the
  agent read the diff and recorded the grant in all 11 cases of one
  repository. Every one of those diffs turned out to be comments or a
  commented-out key. That is 11 gate openings and no catch.
- One mid-loop stop in group A was exactly right. The review found a
  user-visible data loss the Plan had never weighed. The agent refused to
  choose for the person and explained the options on request.
- Two scope forks in group B ended with the person confirming the agent's
  count or its recommendation.

Stops that were not due, or cost more than they bought:

- The authority gate and the proof gate are path-triggered. One change to a
  protected script was a comment rewrap, and the gate still demanded a full
  real-environment proof. The person signed it off by hand.
- One grant stop cost a round trip. The status line said the gate was open,
  but the exact command was below the fold of a long report. The person
  asked what they were needed for.
- The sign-off helper escalation cost 31 minutes of wall clock in group A.

Land outcomes in group A, counted as deduplicated report lines:

| outcome | lines |
| --- | --- |
| landed as a merge commit | 68 |
| stopped at the proof gate | 20 |
| rolled back on a red post-merge suite | 16 |
| merge conflict, primary tree restored | 12 |
| stopped at the authority gate | 10 |
| rolled back on a red post-merge lint | 5 |
| land lock held too long | 6 |

The 16 rollbacks are the strongest evidence here that a land gate pays for
itself. A branch that was green in its own worktree broke the trunk after the
merge, and land put the trunk back.

## Critic misjudgments

Nine shapes, merged across both groups. The count is how many runs showed the
shape.

1. `plan-critic`, approve, 1. The brief pins one mechanism and cites every
   file and line correctly. The critic verifies each claim. It never asks
   what inputs the change runs over. For one producer the mechanism deletes
   the only copy of several fields. Every claim was true, and the change
   still destroyed data.
2. `plan-critic`, approve, 1. Every citation in the brief checks out, and the
   rule the brief derives from them is too general. The critic quoted the
   cited lines back and never asked whether the stated rule follows from
   them. The false rule landed in a durable document.
3. `plan-critic`, approve, 1. The brief asserts a negative about a
   third-party tool, and grounds it in the absence of a key in a config file.
   The critic reported the real claim as verified from that proxy. The tool
   runs the step anyway.
4. `plan-critic`, reject, 1. The only finding is a number inside a motivating
   sentence that no build step reads. The critic's own calibration says a
   reject must cite a finding that blocks an unattended run. The right output
   was an approve with a non-blocking note.
5. `consolidate-critic`, cuts, 1. Two tests assert one proposition at two
   layers, one at the server and one at the parser. The critic judged
   redundancy by the claim asserted, not by the layer, and proposed deleting
   the outer one.
6. `consolidate-critic`, cuts, 2. The cut contradicts a stance the brief
   states, which the critic's own brief puts out of scope. One form deletes
   the test the brief named as its critical-path case. The other gives a
   required safety parameter a silent default, to save churn at the call
   sites.
7. `consolidate-critic`, cuts, 2. The cut target lies outside the change's
   diff. Judging a duplicate by wording overlap led the critic to propose
   deleting pre-existing prose. That widens the change instead of
   consolidating it.
8. `consolidate-critic`, cuts, 1. A broken-pointer rule applied to a pointer
   that hone's own lifecycle guarantees will break. The rule as applied would
   make a whole artifact type impossible to keep.
9. `consolidate-critic`, clean, 1. The critic asserted a filesystem fact from
   the diff and the brief, rather than from the filesystem. The claim rode
   inside a clean verdict, which a caller re-checks least of all.

Shapes 1, 2, and 3 are one failure mode seen three ways. The critic verifies
the citations and not the claim they are cited for. Two of the three slipped
a false statement into a durable document.

A near miss, not counted: one cut asked for three sentences where only two
were duplicates. The author kept the sentence that stated the decision.

Format defect. 13 of 171 reports in group A put the verdict somewhere other
than the last line. A file list or a summary sentence came after it. One
report carried no verdict at all. Both critic briefs ask for a one-line
verdict at the end.

Against all of this the critics caught a lot. In group A all four rejects
held up, and one of them sent the author back to the data and improved the
change. In group B the rejects included a Plan whose named checks would have
gone green having checked nothing.

No person overruled a critic verdict anywhere in the corpus. The author
triaged each finding and recorded the declines. The loop triages the critics,
not the person.

## Friction that is not a hook false alarm

- A Plan-sanctioned edit to a project configuration file is blocked by hone's
  own recommended deny rules, and there is no sanctioned route. The loop
  stopped and did not route around it. The person then applied a patch by
  hand, after three failed attempts.
- The harness permission classifier refused the prescribed re-run after a
  grant, twice. The loop's recovery from the authority gate is to record the
  grant and run the same land command again. The classifier reads a repeated
  command after a refusal as routing around the refusal. The change sat
  committed and granted with only the merge left.
- The same classifier denied a land command outright in one session, and
  denied a worktree removal the Plan had asked for in another. The person ran
  both by hand.
- Sometimes the subject of a change is a file inside the deny perimeter. The
  loop then hands the person a prepared patch and asks them to apply it. Two
  such round trips in group A added no judgment. This recurs for any change
  whose subject is a protected file.
- The person twice had to act on a `nag` finding by hand, because nothing in
  hone acts on it.
- Two messages asked the agent to speak plainly, because a report or a
  question was written in hone's own register.

## What this means for step 5

The handoff judges a guard on three things together. The first is the reach
rate on the models below the floor. The second is how often the hook fired
here, and whether each block was right. The third is what a wrong block costs
in attention. This note supplies the second and part of the third. It
supplies nothing for the first, because these sessions ran on whatever model
the person chose. That part needs the lab.

Cheap, and no false alarm. By the maintainer's rule of 2026-09-20 these stay,
whatever the lab says on opus.

- `guard`: 5 fires, 5 right. Each was a missing test or a durable edit in the
  primary tree, and the agent complied every time.
- `session-start`: 345 runs, no warning printed, no false alarm possible in
  this data. Its observable job was injecting the workflow rule.

False alarms on record. Under the rule each must show a reach that it
stopped.

- `bash-guard`: 28 false alarms of 50 fires. The reaches it stopped are all
  three sabotage reaches in the whole corpus. A wrong block cost agent
  context and one permission prompt. No false alarm was ever escalated to the
  person, and no message anywhere disputes a hook.
- `dirty-guard`: 41 false alarms of 45 fires. It caught 4 real writes into
  the primary tree that no other hook could see. One of them is exactly the
  hole it was built for. A shell working directory had silently reset, and no
  path appeared in the command text. Its wrong blocks cost agent context, and
  its suggested remedy once pointed at a person's own uncommitted work.
- `gate`: 3 false alarms of 92 fires, and none came from the change under
  test. Its catches are 17 real check failures at a turn end, plus 16
  post-merge rollbacks by land. Its cost is the suite lock, which blocked 71
  turn ends and reported no defect.

The `nag` is not a guard and blocks nothing. Its cost is context on every
stop. Two findings repeat until a person acts, and two false-alarm causes
produced 340 of the 342 wrong lines.

The decisions are the maintainer's.
