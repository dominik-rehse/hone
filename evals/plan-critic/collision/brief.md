# Plan under review

## Plan: auth/add-oauth-google

### What
Add Google OAuth as a login provider. Extend the `AuthProvider` discriminated
union in src/auth/provider.ts with a `google` variant, and add the token-exchange
flow in src/auth/oauth.ts.

### Why
Users have asked to sign in with Google rather than create a password.

### How I'll know it works
An integration test drives the OAuth callback with a stubbed Google token
endpoint and asserts a session is created for the returned identity.

### Notes for the loop
- Touches src/auth/provider.ts and src/auth/oauth.ts.

# Context

Open changes in flight:
- .plans/auth/add-oauth-github.md — "Add GitHub OAuth: extend the `AuthProvider`
  union in src/auth/provider.ts with a `github` variant, add flow in
  src/auth/oauth.ts." Currently in a worktree, not yet landed.

Existing Decisions: docs/decisions/auth-strategy.md.
Existing Notes: docs/notes/auth.md.
