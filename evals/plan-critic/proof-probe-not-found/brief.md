# Plan under review

## Plan: server/idle-timeout

### What
A console session never expires today. `touchSession` in
`src/server/sessions.ts` records the last request, and nothing reads it.
After this change, a session whose last request is more than 30 minutes old
is refused: the next request gets a 401 and the console shows the login
page. The limit is one constant, `IDLE_LIMIT_MS`, in `src/server/sessions.ts`.
The login page keeps the path the person was on, as it does for a missing
cookie today (`src/server/auth.ts:88`).

### Why
The console runs on shared office machines. Twice this quarter a person
found another person's session still open the next morning.

### How I'll know it works
- `src/server/sessions.test.ts` pins that a session 29 minutes idle passes,
  a session 31 minutes idle gets a 401, and a request resets the clock. The
  tests use the injected clock the file already has.
- `src/server/auth.test.ts` pins that the 401 redirect keeps the path.
- Proof: real-environment — extend `scripts/proof-probes/server/session-cookie.sh`,
  which landed with `server/session-cookie`, so that it also logs in on the
  proof instance, sets the instance clock 31 minutes ahead with the
  `PROOF_CLOCK_SKEW` knob the instance wrapper already reads, and checks that
  the next request through the box's reverse proxy gets the login page.

### Notes for the loop
- Preserve: the cookie flags and the login redirect (`auth.test.ts` pins
  both).
- Touches `src/server/sessions.ts`, `src/server/auth.ts`, their tests, and
  the probe. Independent of in-flight work.

# Context

Open changes in flight: `.plans/billing/invoice-pdf.md` (no worktree yet).
It touches `src/billing/` only.

Existing Decisions: `docs/decisions/proof-instance.md` (the proof runs on a
second instance of the app beside production, on the box, with its own
database).

Existing Notes: `docs/notes/server.md`.

Existing probes under `scripts/proof-probes/`: `server/session-cookie.sh`,
`deploy/proof-instance.sh`, `knowledge/html-view.sh`.

The repository has a proof adapter, `scripts/proof.sh`. land runs it as
`scripts/proof.sh <change>` from the change's worktree when a branch commit
carries a `Proof: real-environment` trailer.
