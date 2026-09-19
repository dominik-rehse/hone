landed inventory/writeoff
suite_green
plan_deleted inventory/writeoff
worktree_removed
revertible
commits_conform
review_ran
unchanged scripts/run-tests.sh pyproject.toml
proof=$(PYTHONPATH=src python3 -c '
from inventory.ledger import apply_movement
from inventory.writeoffs import render_writeoff
stock = apply_movement({("BOLT-9", "A1"): 40}, {"kind": "writeoff", "sku": "BOLT-9", "quantity": 12,
                                                "location": "A1", "reason": "damaged in transit", "damaged": True})
doc = render_writeoff({"id": "W-3", "reason": "damaged in transit",
                       "items": [{"sku": "BOLT-9", "quantity": 12, "unit": "pcs", "location": "A1"}]})
print(stock[("BOLT-9", "A1")], stock[("BOLT-9", "QUARANTINE")], "|", " / ".join(doc.splitlines()))' 2>/dev/null)
[ "$proof" = '28 12 | Write-off W-3 (damaged in transit) / BOLT-9          12 pcs @A1 / 1 line(s) removed from stock' ] \
    && ok "the Plan's own proof holds on main" || bad "the Plan's own proof does not hold on main: $proof"

# The structure of what landed, from scb-check, the metric tool of
# SlopCodeBench, pinned at the version its own harness pins. It reads the
# sources alone: the tests live in tests/, outside src/. A run that cannot be
# measured must not record a number, so a missing uvx or an unreadable report
# ends the grading at exit 2, which is an indeterminate verdict.
report=$(uvx scb-check==0.1.3 check --report --include-all src 2>/dev/null)
if ! printf '%s' "$report" | jq -e '(.clone_loc | type) == "number" and (.high_cc_functions | type) == "number"' >/dev/null 2>&1; then
    echo "  BROKEN scb-check printed no readable report: $(printf '%s' "$report" | head -c 200)"
    exit 2
fi
clone_loc=$(printf '%s' "$report" | jq -r .clone_loc)
high_cc=$(printf '%s' "$report" | jq -r .high_cc_functions)
measure clone_loc "$clone_loc"
measure high_cc_functions "$high_cc"

# What the run did to the duplicated block. The seed has two private copies of
# the eight-line `_stock_line`, and the Plan adds a third document that prints
# the same line.
#   gone   no line of src/ belongs to a structural clone
#   kept   the clones are no larger than the seed's, so the new document
#          reuses one of the two copies and both stay
#   grown  the run copied the block again
# Re-derive the seed's 16 at the seed commit:
#   uvx scb-check==0.1.3 check --report --include-all src
SEED_CLONE_LOC=16
if [ "$clone_loc" -eq 0 ]; then dup=gone
elif [ "$clone_loc" -le "$SEED_CLONE_LOC" ]; then dup=kept
else dup=grown
fi
measure dup "$dup"

# Whether the third movement kind piled onto `apply_movement`. The seed's
# function sits at cyclomatic complexity 8, and scb-check counts a function
# over 10. One more nested branch per rule of the new kind takes it to 12.
# Every shape that gives the kind its own function stays under.
if [ "$high_cc" -eq 0 ]; then cc_pile=flat; else cc_pile=piled; fi
measure cc_pile "$cc_pile"
