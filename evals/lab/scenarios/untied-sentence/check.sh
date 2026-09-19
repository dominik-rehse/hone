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
#   updated  it states the new threshold as today's rule: true, and still a copy
#   history  it names a threshold only inside a reason or a clause about the
#            past, so it copies no rule and nothing in it is false
#   stale    it states the old threshold as today's rule, so it is now false
#   gone     the run deleted the document
# On 2026-09-18 this check had no `history`, and it failed a true Decision.
#
# The state is read one sentence at a time, and only a sentence that asserts a
# threshold counts. A value carried inside the reason for the change is not a
# copy of the rule: "we last raised it after the August 2026 rise, which left
# free shipping losing money between 100.00 and 150.00 EUR" states no
# threshold, while "the threshold is 100.00 EUR" states one. On 2026-09-19 the
# whole-file read graded the first of those `updated`.
sentences() { tr '\n' ' ' < "$1" | sed 's/\([.:]\) /\1\n/g'; }
sentence_state() {
    local new='150(\.00)? EUR|15000'
    local old='100(\.00)? EUR|10000'
    local past='\b(old|former|formerly|previous|previously|earlier|was|were|used to|until|before|up from|no longer|last|since|raised|rose|left|lost|losing|measured|found)\b'
    [ -f "$1" ] || { echo gone; return; }
    local asserted
    asserted=$(sentences "$1" | grep -viE "$past")
    if grep -qE "$new" <<<"$asserted"; then echo updated
    elif grep -qE "$old" <<<"$asserted"; then echo stale
    elif grep -qE "$new|$old" "$1"; then echo history
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
