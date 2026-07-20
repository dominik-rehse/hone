# `/code-review` in the run loop — rationale and failure modes

Background for step 5 of `run`. The essential instruction lives in `SKILL.md`;
consult this when the review step misbehaves or a shortcut around it looks
tempting.

## Why the command refuses model invocation

The built-in `/code-review` is user-invocation-only (`disable-model-invocation`).
Every model-invocation path refuses it: the Skill tool (`Skill code-review cannot
be used with Skill tool due to disable-model-invocation`), a SlashCommand tool, a
subagent. The refusal is expected, not a dead end. The flag blocks the *model*
from invoking the command, not a *user* — and a slash command in a print-mode
(`-p`) prompt is a user invocation, which is why the nested `claude -p` call in
`SKILL.md` reaches the genuine native reviewer.

## Never hand-roll a substitute

When the refusal appears, the nested `claude -p` call is the one and only next
move. Do not assemble a reviewer — no `Workflow`, no fan-out of `Agent`/`Task`
finders, no "faithful equivalent" or "same multi-agent shape." Each silently
abandons the native review (parallel finders plus a verification pass) this step
exists to reuse, and is a step failure even when it produces findings.

## The JSON envelope is the artifact

The envelope is the proof the native reviewer ran — as the diff proves build and
the gate output proves verify. Before trusting any finding, confirm it is real:
`<out-file>` parses as JSON with `is_error: false`, `subtype: success`, and a
`session_id`. If it is missing, truncated, an error envelope, or absent because
findings came from some other route, the native review did not happen — a step
failure to fix by running the nested call, never a pass to review around. Only
once the envelope confirms do you read the review from its `.result`.

## Why background-and-poll

The multi-agent fan-out takes several minutes — longer than the foreground Bash
timeout, which kills it at ~2 minutes regardless of any inner `timeout`. Run it in
the Bash tool's background mode (not a shell `&`, which the harness won't keep
alive), redirect the JSON to an output file, and poll that file until the run
finishes.

## Don't land on the decoy

The `--allowedTools` allowlist (`Task Agent Read Grep Glob Bash(git *)`) lets the
finders fan out without granting full `bypassPermissions`: a trivial diff reviews
cleanly even in the default mode, but the heavy fan-out wants its tools. Do not
locate, read, or execute a command file on disk, and do not add a marketplace
`code-review` plugin to the path — that plugin is GitHub-PR-shaped (it wants a PR
number and `gh pr comment`) and does not fit a worktree. A literal `/code-review`
in the nested session resolves deterministically to the built-in command, but a
fuzzy skill lookup or disk search can still land on the decoy and make the review
balk.
