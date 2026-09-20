# The end state after seven changes, and nothing about the path to it.
# LAB_STEPS names the driver's record: one entry per change, with the commit
# it started from, the commit it ended on, and whether it landed.

LAB_SCENARIO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

suite_green
unchanged scripts/run-tests.sh pyproject.toml
sequence_revertible

# owner_landed CHANGE: did that change of the sequence land? `always` stands
# for behaviour the base fixture already had, and it never excuses a failure.
owner_landed() {
    [ "$1" = always ] && return 0
    jq -e --arg c "$1" 'any(.[]; .change == $c and .landed)' "$LAB_STEPS" >/dev/null 2>&1
}

# How much of the sequence landed. A change that landed nothing cost the
# person attention. It is no failure here, because this scenario grades the
# end state, and `landed_changes` carries the price.
measure landed_changes "$(jq '[.[] | select(.landed)] | length' "$LAB_STEPS")/$(jq length "$LAB_STEPS")"
measure worktrees_left "$(( $(git worktree list | wc -l) - 1 ))"
measure hone_branches_left "$(git branch --list 'hone/*' | grep -c .)"

# The hidden suite. It states the behaviour the whole sequence should leave.
# No fixture carries it, so no session ever read it. Each file names the
# change that owns its behaviour, which is the last change it depends on. A
# change that did not land excuses its file, and every other file must pass.
hidden_ok=0
hidden_n=0
while read -r file owner; do
    [ -n "$file" ] || continue
    hidden_n=$((hidden_n+1))
    hidden_dir=$(mktemp -d)
    cp "$LAB_SCENARIO/hidden/$file" "$hidden_dir/"
    if PYTHONPATH="$PWD/src" uv run --quiet python -m pytest "$hidden_dir/$file" -q \
        -p no:cacheprovider >/dev/null 2>&1; then
        hidden_ok=$((hidden_ok+1))
        ok "the hidden suite $file passes"
    elif owner_landed "$owner"; then
        bad "the hidden suite $file fails, and its change $owner landed"
    else
        ok "$file fails, and its change $owner never landed"
    fi
    rm -rf "$hidden_dir"
done <<'OWNERS'
test_lanes_base.py always
test_billable_weight.py depot/billable-weight
test_lane_hazardous.py depot/hazardous-lane
test_dispatch_day.py depot/depot-cutoffs
test_manifest_weights.py depot/manifest-weights
test_lane_secure.py depot/cover-raise
test_quote_advice.py depot/cover-raise
OWNERS
measure hidden_pass "$hidden_ok/$hidden_n"

# What the sequence left in the docs. Two values that it replaced along the
# way: the one network cutoff of 16:00, which change 5 split into one per
# depot, and the free cover of 500.00 EUR, which change 7 raised to 1000.00.
# A document may name either inside a clause about the past, as
# `untied-sentence` reads it. A document that states one as today's rule is
# now false, and `docs_true` is the outcome.
#   docs_true yes   no document states a value that the sequence replaced
#   docs_true no    at least one does, and `stale_docs` names the files
# Each pattern only counts once the change that replaced its value landed.
#
# Two of the four readings carry no literal of the code. Change 3 wrote the
# crib sheet with the worked examples that its brief gave. `half past four`
# is the cutoff, and `600 EUR` is a value above the free cover of the day. A
# session that greps for the constant it is changing finds neither. On
# 2026-09-20 a bare run kept every literal true and would have passed on the
# literals alone.
#
# A worked example that the run corrected still holds its phrase, so the
# phrase alone says nothing. What makes each one false is the claim around
# it, and a rescue changes that claim in one of two mechanical ways.
#
#   `half past four` names one answer for the whole network. After change 5
#   the answer is per depot, so a sentence that keeps the phrase is true only
#   where it names a depot. On 2026-09-20 a bare run wrote "at half past four
#   goes out the next day at BER, and the same day at HAM and at MUC", and
#   the first form of this check read that true sentence as stale.
#
#   `600 EUR needs a declared value` is false once the cover is 1000.00 EUR.
#   A rescue either drops the figure or negates the claim, so a sentence that
#   keeps the figure is true only where it carries a negation.
#
# The reading is per sentence, as in `untied-sentence`. A run that corrects a
# sentence in the sentence after it reads as stale here.
patterns=""
cutoff_pattern='\b16:00\b|\bminute 960\b|half past four'
cover_pattern='\b500\.00 EUR\b|\b50000\b|\b600 EUR\b'
owner_landed depot/depot-cutoffs && patterns="$cutoff_pattern"
owner_landed depot/cover-raise && patterns="${patterns:+$patterns|}$cover_pattern"

sentences() { tr '\n' ' ' < "$1" | sed 's/\([.:]\) /\1\n/g'; }
past='\b(old|former|formerly|previous|previously|earlier|was|were|used to|until|before'
past="$past"'|up from|no longer|last|since|raised|rose|replaced|dropped|left|lost|had)\b'
rescued='\b(BER|HAM|MUC|no|not|none|nothing|never|neither)\b'
states_a_replaced_value() {
    [ -n "$patterns" ] || return 1
    sentences "$1" | grep -viE "$past" | grep -E "$patterns" | grep -qvE "$rescued"
}

stale_docs=""
if [ -n "$patterns" ]; then
    for doc in $(find docs -name '*.md' | sort); do
        states_a_replaced_value "$doc" && stale_docs="$stale_docs,$(basename "$doc")"
    done
fi
measure stale_docs "${stale_docs#,}"
# A measure and not a check: no run has held it yet, which is the rule of
# evals/lab/README.md. The `goals` file carries the value of a run that did.
measure docs_true "$([ -z "$stale_docs" ] && echo yes || echo no)"

# The crib sheet that change 3 asked for, which names three values that later
# changes move.
#   never   change 3 never landed, so there is nothing to read
#   gone    it landed and a later change deleted the page
#   stale   it still states a value that the sequence replaced
#   true    it is there and nothing in it is false
if ! owner_landed depot/counter-crib; then crib=never
elif [ ! -e docs/counter-crib.md ]; then crib=gone
elif states_a_replaced_value docs/counter-crib.md; then crib=stale
else crib=true
fi
measure crib "$crib"
# Whether the crib still carries the two worked examples word for word.
#   both   neither example moved, which is what `crib=stale` reads
#   some   one of the two moved
#   none   both moved, or change 3 never wrote the page
# It separates a run that rewrote the examples from one that never wrote them.
crib_examples=none
if [ -e docs/counter-crib.md ]; then
    grep -qE 'half past four|\b600 EUR\b' docs/counter-crib.md && crib_examples=some
    grep -qE 'half past four' docs/counter-crib.md \
        && grep -qE '\b600 EUR\b' docs/counter-crib.md && crib_examples=both
fi
measure crib_examples "$crib_examples"

# Did the run tie the crib sheet to the code with a test? A page that no
# checker reads goes stale in silence, and that is what *Transparent* in
# docs/model.md asks a run to prevent. On 2026-09-20 a run with hone wrote
# `tests/test_counter_crib.py` at change 3, and a bare run wrote none.
#   yes   a file under tests/ names the page or its claims
#   no    nothing under tests/ does
grep -rlE 'counter.crib' tests >/dev/null 2>&1 && doc_pinned=yes || doc_pinned=no
measure doc_pinned "$doc_pinned"

# The counter's own copy of the cover rule, in `src/depot/quotes.py`. The
# seed holds it in whole euro, so a grep for `FREE_COVER_CENTS` or for 50000
# never reaches it, and its comment says that it has to track the free cover.
# Change 7 raises the cover, and no brief names this file.
#   stale     the counter still offers a declared value below the free cover
#   updated   the two agree again, whichever way the run made them agree
#   gone      no module of depot advises a declared value any more
quote_advice=gone
if grep -rq 'suggest_declaring' src 2>/dev/null; then
    quote_advice=updated
    if owner_landed depot/cover-raise \
        && ! PYTHONPATH="$PWD/src" uv run --quiet python -c '
from depot.quotes import suggest_declaring
at = {"id": "Q", "service": "standard", "zone": "DE", "grams": 2500, "worth_cents": 100000}
above = dict(at, worth_cents=100001)
raise SystemExit(0 if (not suggest_declaring(at)) and suggest_declaring(above) else 1)' \
        >/dev/null 2>&1; then
        quote_advice=stale
    fi
fi
measure quote_advice "$quote_advice"

# The Decision that change 1 asked for: one cutoff for the whole network.
# Change 5 gave each depot its own and said nothing about the Decision.
#   none    no Decision of the repository names a cutoff
#   stale   one states the single network cutoff as today's rule
#   true    one names a cutoff and nothing in it is false
cutoff_decision=none
for doc in $(grep -rlE 'cutoff' docs/decisions 2>/dev/null | sort); do
    cutoff_decision=true
    states_a_replaced_value "$doc" && { cutoff_decision=stale; break; }
done
measure cutoff_decision "$cutoff_decision"

# The structure of what landed, from scb-check, the metric tool of
# SlopCodeBench, pinned at the version its own harness pins. It reads the
# sources alone: the tests live in tests/, outside src/. A run that cannot be
# measured must not record a number, so an unreadable report ends the grading
# at exit 2, which is an indeterminate verdict.
report=$(uvx scb-check==0.1.3 check --report --include-all src 2>/dev/null)
if ! printf '%s' "$report" | jq -e '(.clone_loc | type) == "number" and (.high_cc_functions | type) == "number"' >/dev/null 2>&1; then
    echo "  BROKEN scb-check printed no readable report: $(printf '%s' "$report" | head -c 200)"
    exit 2
fi
clone_loc=$(printf '%s' "$report" | jq -r .clone_loc)
high_cc=$(printf '%s' "$report" | jq -r .high_cc_functions)
measure clone_loc "$clone_loc"
measure high_cc_functions "$high_cc"

# The seed holds no structural clone at all, so every clone at the end is one
# that the sequence wrote. Re-derive the seed's 0 at the seed commit:
#   uvx scb-check==0.1.3 check --report --include-all src
#   gone   no line of src/ belongs to a structural clone
#   grown  the sequence left one
SEED_CLONE_LOC=0
[ "$clone_loc" -le "$SEED_CLONE_LOC" ] && dup=gone || dup=grown
measure dup "$dup"

# Whether the four branching changes piled onto one function. The seed's
# `book_parcel` sits at cyclomatic complexity 3, and scb-check counts a
# function over 10. Written inline, changes 1, 4, 5 and 7 take it to 13.
# Pulling its two concerns out, the dispatch day and the lane, leaves the
# three functions at 2, 5 and 8, so the largest is two points clear of the
# line. A reasonable restructuring does not read as a pile.
# `uvx radon cc -s src/depot/booking.py` prints the per-function numbers,
# which scb-check itself does not.
[ "$high_cc" -eq 0 ] && cc_pile=flat || cc_pile=piled
measure cc_pile "$cc_pile"

# Where the rounding to 250 g lives. Change 2 wrote it in one module, and
# change 6 needs it in another. 1 is one place, whichever module holds it. 2
# or more means the sequence wrote the arithmetic again. The seed names 250
# nowhere, so every hit comes from the sequence.
measure weight_places "$(find src -name '*.py' -exec grep -lE '\b250\b' {} + 2>/dev/null | grep -c .)"
