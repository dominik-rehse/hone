# Change under review (consolidate step)

## Plan (in hand, to be deleted): auth/password-hashing
Move password hashing to argon2id.

## Diff summary
- src/auth/hash.ts: `hashPassword`/`verifyPassword` now use argon2id
  (m=19456, t=2, p=1); legacy bcrypt hashes still verify and are re-hashed with
  argon2id on the next successful login.
- src/auth/hash.test.ts: new-hash round-trip, legacy verify, upgrade-on-login.

## What this change left behind (durable layer)
- New Decision docs/decisions/password-hashing.md, full text:

  > # Password hashing
  > `hashPassword` uses argon2id with m=19456, t=2, p=1. `verifyPassword`
  > accepts both argon2id and legacy bcrypt hashes. When a legacy hash
  > verifies, the password is re-hashed with argon2id and stored. New hashes
  > are always argon2id.

- docs/notes/auth.md unchanged.

## Types / abstractions touched
- none new.
