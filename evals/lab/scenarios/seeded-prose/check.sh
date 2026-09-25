landed shipping/free-from-150
suite_green
plan_deleted shipping/free-from-150
worktree_removed
revertible
commits_conform
review_ran
[ "$(node -e 'const { shippingCents: s } = require("./src/shipping/rates.js"); console.log(s({ totalCents: 14999, country: "DE" }), s({ totalCents: 15000, country: "DE" }))' 2>/dev/null)" = "490 0" ] \
    && ok "the threshold is 150.00 EUR on main" || bad "the Plan's own proof does not hold on main"

# What became of the Note's seeded list of behaviours. A Note is a map and one
# invariant, so every sentence on a rate or on the threshold is a repeat.
#   cut      the list is gone, and the map and the invariant are still there
#   partly   the sentence on the threshold is gone, and a rate stays
#   updated  the Note states the new threshold: true, and still a copy
#   stale    the Note states the old threshold alone, so it is now false
#   lost     the run deleted the invariant
note_state() {
    local file=docs/notes/shipping.md
    if ! grep -E '^Invariant: ' "$file" >/dev/null 2>&1; then echo lost
    elif grep -E '150(\.00)? EUR|15000' "$file" >/dev/null; then echo updated
    elif grep -E '100(\.00)? EUR|10000' "$file" >/dev/null; then echo stale
    elif grep -E '[469]\.90 EUR' "$file" >/dev/null; then echo partly
    else echo cut
    fi
}

# What became of the Decision's seeded paragraph, which restated the function
# by its identifiers. A Decision may name the new threshold beside the reason
# for it. That is a decision and its why, so it counts as `cut`.
#   cut      no restatement of the function is left, and the reason is there.
#            The Decision may still name the constant it settled, beside why
#   updated  a sentence still restates the function: an identifier beside the
#            value it holds or the behaviour it has
#   stale    the Decision states the old threshold alone, so it is now false
#   lost     the run deleted the reason for flat rates
#
# The restatement is read one sentence at a time. The reason for a threshold
# names both values in prose ("the orders between 100.00 and 150.00 EUR, which
# shipped free until then"), and that sentence is true of the past rather than
# a copy of the code. Naming the identifier alone is not a copy either: it is
# what the Decision decided. A copy is the two together in one sentence.
decision_restatement() {
    tr '\n' ' ' < "$1" | sed 's/\([.:]\) /\1\n/g' \
        | grep -E 'FREE_FROM_CENTS|shippingCents|RATES|REST_OF_EU' \
        | grep -qE '\b(10000|15000)\b|[469]\.90|returns|falls back|looks .*up|at least'
}
decision_state() {
    local file=docs/decisions/shipping-rates.md
    if ! grep -E 'by weight|weight bands' "$file" >/dev/null 2>&1; then echo lost
    elif grep -E '100(\.00)? EUR|10000' "$file" >/dev/null \
         && ! grep -E '150(\.00)? EUR|15000' "$file" >/dev/null; then echo stale
    elif decision_restatement "$file"; then echo updated
    else echo cut
    fi
}
goal note_spec "$(note_state)" cut
goal decision_restates "$(decision_state)" cut

# Where the run said it stood. It only measures.
progress_lines
