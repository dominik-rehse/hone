# `/code-review` in the run loop: rationale and failure modes

Background for step 5 of `run`. The essential instruction lives in `SKILL.md`.
Consult this when the review step misbehaves or a shortcut around it looks
tempting.

## Why the command refuses model invocation

The built-in `/code-review` is user-invocation-only (`disable-model-invocation`).
Every model-invocation path refuses it: the Skill tool (`Skill code-review cannot
be used with Skill tool due to disable-model-invocation`), a SlashCommand tool, a
subagent. The flag blocks the *model* from invoking the command, not a *user*.
A slash command in a print-mode
(`-p`) prompt is a user invocation, which is why the nested `claude -p` call in
`SKILL.md` reaches the genuine native reviewer.

## Never hand-roll a substitute

When the refusal appears, the nested `claude -p` call is the one and only next
move. Do not assemble a reviewer: no `Workflow`, no `Agent`/`Task` reviewers of
your own, no "faithful equivalent." Each silently abandons the native review
this step exists to reuse. Each is a step failure even when it produces
findings.

## The JSON envelope is the proof the review ran

The envelope proves the native reviewer ran, the same way the diff proves build
and the gate output proves verify. Before trusting any finding, confirm it is real:
`<out-file>` parses as JSON with `is_error: false`, `subtype: success`, and a
`session_id`. It did not happen if the file is missing after the background
task ended, or truncated, or an error envelope. Nor if the findings came from
some other route. That is a step failure to fix by running the nested call, not
a pass to review around. Only once the envelope confirms do you read the review
from its `.result`.

Those three fields are the whole check. The rest of the envelope is not a
verdict on the review. `permission_denials` lists what the allowlist refused,
and it refuses on purpose. The reviewer reaches past `git` and the read tools,
so almost every envelope carries a denial. Your brief already holds the diff
and the Plan. What a denial costs the reviewer is a check of its own, never the
change. `num_turns` and `subagent_stats.spawned` read `0` on reviews that came
back complete, so neither is a signal: the command does not count the subagent
it reviews in. Another review model gets another recipe, which is what
`--review-model` switches in the lab. Take any of it as a fault and you pay for
a second review.

## Why background-and-poll

A review can outrun the foreground Bash timeout, which kills it at ~2 minutes
regardless of any inner `timeout`. Run it in
the Bash tool's background mode (not a shell `&`, which the harness won't keep
alive). Redirect the JSON to `<out-file>.part` and rename it to `<out-file>`
when the call ends, as the command in the skill does. Both files sit in a
private directory from `mktemp -d`, so no other session writes there and no
earlier run left a file there. Then `<out-file>` exists only for this run's
finished review. An empty file there would read as a dead review, and the step
runs once.

## Don't land on the decoy

The `--allowedTools` allowlist (`Task Agent Read Grep Glob Bash(git *)`) keeps
the review off full `bypassPermissions`. Copy it as written and leave it there.
Do not
locate, read, or execute a command file on disk, and do not add a marketplace
`code-review` plugin to the path. That plugin is GitHub-PR-shaped (it wants a PR
number and `gh pr comment`) and does not fit a worktree. A literal `/code-review`
in the nested session resolves deterministically to the built-in command. But a
fuzzy skill lookup or disk search can still land on the decoy and make the review
balk.
