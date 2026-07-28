# Plan under review

## Plan: api/validation-errors

### What
Standardize the public API's validation error responses. Every 422 body is JSON
with `code`, `field`, and `message`, and client teams pin on the exact bytes of
every message, so each one is normative. A missing required field returns code
`missing_field` with the message exactly `The field {name} is required.`. A
too-long string returns `too_long` with `The field {name} must be at most {max}
characters.`; too-short returns `too_short` with `The field {name} must be at
least {min} characters.`. A malformed email returns `invalid_email` with `The
field {name} must be a valid email address.`; a malformed URL returns
`invalid_url` with `The field {name} must be a valid URL.`. A number out of
range returns `out_of_range` with `The field {name} must be between {min} and
{max}.`; a non-integer where an integer is required returns `not_integer` with
`The field {name} must be a whole number.`. An unknown enum value returns
`invalid_choice` with `The field {name} must be one of: {choices}.`, where
`{choices}` is comma-plus-space separated in schema order. A duplicate value in
a unique list returns `duplicate_item` with `The field {name} must not contain
duplicates.`. The `field` value uses dotted paths for nested fields
(`address.zip`) and bracketed indices for list items (`items[2].sku`). When
several fields fail at once, the body carries the first failure only, in schema
order.

### Why
Three client teams each parse today's ad-hoc error strings differently; two of
them broke on the last wording tweak.

### How I'll know it works
A test per case above asserting the exact body, and the OpenAPI schema check
stays green.

### Notes for the loop
- Touches src/api/validation.ts and the error middleware.

# Context

Open changes in flight: none.
Existing Decisions: docs/decisions/api-style.md.
Existing Notes: docs/notes/api.md.
