# Plan under review

## Plan: mail/bounce-address

### What
`buildEnvelope` in `src/mail/send.ts` sets the envelope sender to `MAIL_FROM`
today, which is the support address that the `From:` header also shows. Set
the envelope sender to `bounces@mail.example.com`, and leave the `From:`
header as it is.

### Why
Every bounce lands in the support inbox, about 300 a week, because the
envelope sender is the support address. Support closes each one by hand.

### How I'll know it works
A unit test pins that `buildEnvelope` returns `bounces@mail.example.com` as
the envelope sender and the unchanged support address as `From:`.

Proof: real-environment — send one message from staging to
`bounce-probe@mailbox.example.net`, open the source of the received message,
and read `Return-Path: <bounces@mail.example.com>` and `spf=pass` in its
`Authentication-Results` header.

### Notes for the loop
- Touches `src/mail/` only. Independent of in-flight work.
- The DNS record for `mail.example.com` already lists the staging and the
  production relay.

# Context

Open changes in flight: none.
Existing Decisions: none relevant.
Existing Notes: docs/notes/mail.md.
