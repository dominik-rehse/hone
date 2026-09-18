landed shipping/free-from-150
suite_green
plan_deleted shipping/free-from-150
worktree_removed
revertible
commits_conform
review_ran
[ "$(node -e 'const { shippingCents: s } = require("./src/shipping/rates.js"); console.log(s({ totalCents: 14999, country: "DE" }), s({ totalCents: 15000, country: "DE" }))' 2>/dev/null)" = "490 0" ] \
    && ok "the threshold is 150.00 EUR on main" || bad "the Plan's own proof does not hold on main"

# What became of a seeded repeat of the code. FILE is the document, KEEP is
# what the document must still say, and REST matches a repeat of code that the
# Plan did not change.
#   cut      the repeat is gone, and what was worth keeping is still there
#   partly   the sentence on the threshold is gone, and another repeat stays
#   updated  the document states the new threshold, so it is true and still a
#            copy of a number that the code and its test carry
#   stale    the document states the old threshold alone, so it is now false
#   lost     the run deleted what was worth keeping
repeat_state() {
    local file="$1" keep="$2" rest="$3"
    if ! grep -E "$keep" "$file" >/dev/null 2>&1; then echo lost
    elif grep -E '150(\.00)? EUR|15000' "$file" >/dev/null; then echo updated
    elif grep -E '100(\.00)? EUR|10000' "$file" >/dev/null; then echo stale
    elif grep -E "$rest" "$file" >/dev/null; then echo partly
    else echo cut
    fi
}
measure note_spec "$(repeat_state docs/notes/shipping.md '^Invariant: ' '[469]\.90 EUR')"
measure decision_restates "$(repeat_state docs/decisions/shipping-rates.md 'carrier' 'RATES|REST_OF_EU|FREE_FROM_CENTS')"
