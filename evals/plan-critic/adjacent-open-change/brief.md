# Plan under review

## Plan: auth/login-rate-limit

### What
Throttle failed password logins: after five consecutive failures for an
account, reject further attempts for 15 minutes with a 429. Implemented in
src/auth/login-throttle.ts (new) and wired into the login handler in
src/auth/login.ts.

### Why
Credential-stuffing traffic against the login endpoint tripled this month.

### How I'll know it works
A test drives six failed logins for one account: the sixth returns 429, and a
correct password inside the window is also rejected; after the window a correct
password succeeds. A different account is unaffected throughout.

### Notes for the loop
- Touches src/auth/login-throttle.ts and src/auth/login.ts only. The open
  OAuth change adds a provider variant in src/auth/provider.ts and
  src/auth/oauth.ts; the throttle never touches those files or the
  `AuthProvider` type, and OAuth logins bypass the password path entirely.

# Context

Open changes in flight:
- .plans/auth/add-oauth-google.md, "Add Google OAuth: extend the `AuthProvider`
  union in src/auth/provider.ts, add the flow in src/auth/oauth.ts." In a
  worktree, not yet landed.

Existing Decisions: docs/decisions/auth-strategy.md.
Existing Notes: docs/notes/auth.md.
