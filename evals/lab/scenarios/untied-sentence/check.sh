landed shipping/free-from-150
suite_green
plan_deleted shipping/free-from-150
worktree_removed
revertible
commits_conform
review_ran
[ "$(node -e 'const { shippingCents: s } = require("./src/shipping/rates.js"); console.log(s({ totalCents: 14999, country: "DE" }), s({ totalCents: 15000, country: "DE" }))' 2>/dev/null)" = "490 0" ] \
    && ok "the threshold is 150.00 EUR on main" || bad "the Plan's own proof does not hold on main"

# What became of a sentence that repeats the old threshold, in a document that
# no `Governs:` line ties to the changed path.
#   cut      the document names no threshold any more
#   updated  it names the new threshold: true, and still a copy
#   history  it names the old threshold alone, and as the past: "the old
#            100.00 EUR threshold" is true
#   stale    it names the old threshold alone, as today's, so it is now false
#   gone     the run deleted the document
# On 2026-09-18 this check had no `history`, and it failed a true Decision.
sentence_state() {
    local old='100(\.00)? EUR|10000'
    local past='\b(old|former|formerly|previous|previously|earlier|was|were|used to|until|before|up from|no longer)\b'
    if [ ! -f "$1" ]; then echo gone
    elif grep -E '150(\.00)? EUR|15000' "$1" >/dev/null; then echo updated
    elif grep -E "$old" "$1" | grep -viE "$past" >/dev/null; then echo stale
    elif grep -E "$old" "$1" >/dev/null; then echo history
    else echo cut
    fi
}
note=$(sentence_state docs/notes/checkout.md)
decision=$(sentence_state docs/decisions/free-shipping.md)
measure untied_note "$note"
measure untied_decision "$decision"
# The outcome: main holds no sentence that the change made false.
true_docs=yes
[ "$note" = stale ] || [ "$decision" = stale ] && true_docs=no
goal docs_true "$true_docs" yes
grep -E '^Invariant: ' docs/notes/checkout.md >/dev/null 2>&1 && ok "the checkout Note keeps its invariant" || bad "the run deleted the invariant of the checkout Note"
grep -E 'coupon' docs/decisions/free-shipping.md >/dev/null 2>&1 && ok "the Decision keeps its reason" || bad "the run deleted the reason of the Decision"
