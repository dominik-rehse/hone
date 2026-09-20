# The well-structured outcome, on a Python fixture, measured by `scb-check`,
# the metric tool of SlopCodeBench (docs/spikes/2026-09-18-slopcodebench-first-look.md).
# Two things are seeded, and each one has its own measure.
#
# `_stock_line` exists twice, as a private copy in each of the two documents,
# and the Plan adds a third document that prints the same line. So the change
# is the third use, where the rule of three says to extract. `clone_loc` counts
# the lines that belong to a structural clone.
#
# `apply_movement` already handles four kinds of movement inline, in 64 lines
# at cyclomatic complexity 7. The Plan's fifth kind is the heavy one: it
# carries several lines, each one checked before any stock moves. Written as
# one more branch in the same function, that is 87 lines at complexity 15, and
# the tool counts a function over 10. `high_cc_functions` counts that.
#
# The margins matter more than the numbers. A run that only gives the NEW kind
# its own function leaves `apply_movement` at 8 and the new function at 8, so
# the smallest reasonable change stays two points clear of the line. Four
# inline kinds are not a pile: a reviewer calls such a function easy to read
# (docs/spikes/2026-09-19-python-structure-baseline.md).
#
# The fixture needs `uv` and `uvx` on PATH: `uvx` for the measure, and `uv` for
# the test adapter, which runs `uv run pytest`. The base seed installed the
# Node adapter, so this seed removes every Node trace and runs hone's own
# setup.sh again, which gives the fixture what a real Python consumer gets.
command -v uv >/dev/null && command -v uvx >/dev/null \
    || { echo "the python-structure fixture needs uv and uvx on PATH" >&2; exit 1; }

rm -f package.json scripts/run-tests.sh
cat > pyproject.toml <<'EOF'
[project]
name = "lab-fixture"
version = "0.0.0"
requires-python = ">=3.11"
dependencies = []

[dependency-groups]
dev = ["pytest>=8"]

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
EOF
CLAUDE_PROJECT_DIR="$PWD" bash "$LAB_PLUGIN/scripts/setup.sh" >/dev/null 2>&1 \
    || { echo "hone's setup.sh failed on the python-structure fixture" >&2; exit 1; }
grep -q 'uv run pytest' scripts/run-tests.sh \
    || { echo "setup.sh installed no Python test adapter" >&2; exit 1; }
# uv builds an environment per tree, and no commit may carry one. uv.lock is
# committed, so every tree resolves the same versions. The run has its own
# HOME, and uv keeps its cache under HOME, so the first call in a worktree
# fetches about 7 MB of wheels. Every call after that is offline.
# Python and pytest also write beside the source, and a tracked .pyc leaves the
# primary tree dirty after every suite run, which `revertible` reads as a fail.
for entry in '.venv/' '__pycache__/' '.pytest_cache/'; do
    grep -qxF "$entry" .gitignore || printf '%s\n' "$entry" >> .gitignore
done

mkdir -p src/inventory tests docs/notes .plans/inventory
cat > src/inventory/__init__.py <<'PY'
"""Stock movements and the documents that report them."""
PY
cat > src/inventory/receipts.py <<'PY'
"""The document a warehouse writes when goods arrive."""


def _stock_line(sku, quantity, unit, location):
    code = location.upper().replace(" ", "-")
    amount = round(float(quantity), 2)
    if amount == int(amount):
        printed = str(int(amount))
    else:
        printed = f"{amount:.2f}"
    return f"{sku:<10}{printed:>8} {unit:<4}@{code}"


def render_receipt(receipt):
    lines = [f"Receipt {receipt['id']} from {receipt['supplier']}"]
    for item in receipt["items"]:
        lines.append(_stock_line(item["sku"], item["quantity"], item["unit"], item["location"]))
    return "\n".join(lines)
PY
cat > src/inventory/transfers.py <<'PY'
"""The document that follows goods from one place to another."""


def _stock_line(sku, quantity, unit, location):
    code = location.upper().replace(" ", "-")
    amount = round(float(quantity), 2)
    if amount == int(amount):
        printed = str(int(amount))
    else:
        printed = f"{amount:.2f}"
    return f"{sku:<10}{printed:>8} {unit:<4}@{code}"


def render_transfer(transfer):
    lines = [f"Transfer {transfer['id']}: {transfer['origin']} to {transfer['destination']}"]
    for item in transfer["items"]:
        lines.append(_stock_line(item["sku"], item["quantity"], item["unit"], transfer["destination"]))
    return "\n".join(lines)
PY
cat > src/inventory/ledger.py <<'PY'
"""Stock per location, and the movements that change it."""

LOCATIONS = ("A1", "A2", "B1", "QUARANTINE")


def apply_movement(stock, movement):
    """Apply one movement and give the new stock back.

    A movement always carries a kind. What else it carries depends on the
    kind, so each kind reads its own fields:

      receipt     sku, quantity, location, supplier
      transfer    sku, quantity, origin, destination, optional partial
      adjustment  sku, quantity (the counted amount), location
      return      sku, quantity, location, customer

    The stock maps (sku, location) to the quantity held there. Two
    reporting keys sit beside it, ("variance", sku) and ("returned", sku),
    which the monthly figures read.
    """
    kind = movement["kind"]
    updated = dict(stock)
    if kind == "receipt":
        # Goods arrive from a supplier and land at one location. The
        # supplier rides along for the receipt document, and the ledger
        # itself keeps no trace of it.
        sku = movement["sku"]
        quantity = movement["quantity"]
        location = movement["location"]
        held = updated.get((sku, location), 0)
        updated[(sku, location)] = held + quantity
    elif kind == "transfer":
        # Goods move between two of our own locations. A transfer marked
        # partial moves whatever the origin holds, which is what the floor
        # does when a pallet is short and the truck is already waiting.
        sku = movement["sku"]
        quantity = movement["quantity"]
        origin = movement["origin"]
        destination = movement["destination"]
        held = updated.get((sku, origin), 0)
        if held < quantity:
            if movement.get("partial"):
                quantity = held
            else:
                raise ValueError(f"not enough {sku} at {origin}")
        updated[(sku, origin)] = held - quantity
        updated[(sku, destination)] = updated.get((sku, destination), 0) + quantity
    elif kind == "adjustment":
        # A stocktake counted the shelf, and the count wins. The difference
        # goes to the variance of the sku, which accounting reads monthly
        # and which nothing else in here ever touches.
        sku = movement["sku"]
        counted = movement["quantity"]
        location = movement["location"]
        held = updated.get((sku, location), 0)
        updated[(sku, location)] = counted
        updated[("variance", sku)] = updated.get(("variance", sku), 0) + counted - held
    elif kind == "return":
        # A customer sent goods back. They go to the location the return
        # names, and the returned total feeds the quality report. Whether
        # they are saleable again is the quality team's call, not ours.
        sku = movement["sku"]
        quantity = movement["quantity"]
        location = movement["location"]
        updated[(sku, location)] = updated.get((sku, location), 0) + quantity
        updated[("returned", sku)] = updated.get(("returned", sku), 0) + quantity
    else:
        raise ValueError(f"unknown movement kind {kind}")
    return updated
PY
cat > tests/test_receipts.py <<'PY'
from inventory.receipts import render_receipt


def test_prints_the_supplier_and_one_padded_stock_line():
    receipt = {
        "id": "R-7",
        "supplier": "Acme",
        "items": [{"sku": "BOLT-9", "quantity": 12, "unit": "pcs", "location": "a1"}],
    }
    assert render_receipt(receipt) == "Receipt R-7 from Acme\nBOLT-9          12 pcs @A1"
PY
cat > tests/test_transfers.py <<'PY'
from inventory.transfers import render_transfer


def test_rounds_a_fractional_quantity_to_two_decimals():
    transfer = {
        "id": "T-2",
        "origin": "A1",
        "destination": "b1",
        "items": [{"sku": "SAND", "quantity": 2.505, "unit": "kg"}],
    }
    assert render_transfer(transfer) == "Transfer T-2: A1 to b1\nSAND          2.50 kg  @B1"
PY
cat > tests/test_ledger.py <<'PY'
import pytest

from inventory.ledger import apply_movement


def test_a_receipt_adds_to_the_stock_of_its_location():
    stock = apply_movement({}, {"kind": "receipt", "sku": "BOLT-9", "quantity": 40, "location": "A1"})
    assert stock == {("BOLT-9", "A1"): 40}


def test_a_transfer_moves_the_quantity_between_two_locations():
    stock = apply_movement(
        {("BOLT-9", "A1"): 40},
        {"kind": "transfer", "sku": "BOLT-9", "quantity": 15, "origin": "A1", "destination": "B1"},
    )
    assert stock == {("BOLT-9", "A1"): 25, ("BOLT-9", "B1"): 15}


def test_a_transfer_refuses_a_quantity_the_origin_does_not_hold():
    with pytest.raises(ValueError, match="not enough BOLT-9 at A1"):
        apply_movement(
            {("BOLT-9", "A1"): 5},
            {"kind": "transfer", "sku": "BOLT-9", "quantity": 15, "origin": "A1", "destination": "B1"},
        )


def test_a_partial_transfer_moves_what_the_origin_holds():
    stock = apply_movement(
        {("BOLT-9", "A1"): 5},
        {"kind": "transfer", "sku": "BOLT-9", "quantity": 15, "origin": "A1",
         "destination": "B1", "partial": True},
    )
    assert stock == {("BOLT-9", "A1"): 0, ("BOLT-9", "B1"): 5}


def test_an_adjustment_sets_the_count_and_records_the_variance():
    stock = apply_movement(
        {("BOLT-9", "A1"): 40},
        {"kind": "adjustment", "sku": "BOLT-9", "quantity": 37, "location": "A1"},
    )
    assert stock == {("BOLT-9", "A1"): 37, ("variance", "BOLT-9"): -3}


def test_a_return_adds_the_goods_back_and_counts_them():
    stock = apply_movement(
        {("BOLT-9", "A1"): 40},
        {"kind": "return", "sku": "BOLT-9", "quantity": 2, "location": "A1", "customer": "Acme"},
    )
    assert stock == {("BOLT-9", "A1"): 42, ("returned", "BOLT-9"): 2}


def test_an_unknown_kind_raises():
    with pytest.raises(ValueError, match="unknown movement kind audit"):
        apply_movement({}, {"kind": "audit", "sku": "BOLT-9", "quantity": 1})
PY
cat > docs/notes/inventory.md <<'MD'
# inventory

Governs: `src/inventory/`

Map: `receipts.py` and `transfers.py` render the two documents a warehouse
files. `ledger.py` holds the stock per location and applies one movement to it.

Invariant: the ledger holds a quantity in the unit it arrived in, and only a
document rounds it for print.
MD
cat > .plans/inventory/writeoff.md <<'PLAN'
# Plan: inventory/writeoff

## What
Goods that are damaged or lost leave stock as a write-off. Teach
`apply_movement` in `src/inventory/ledger.py` the movement kind `writeoff`. One
write-off carries a `reason` and one or more `lines`, and each line names a
`sku`, a `quantity`, a `unit`, and a `location`. With no non-empty `reason` it
raises `a write-off needs a reason`, and with no line
`a write-off needs at least one line`. A line whose quantity is not positive
raises `a write-off line needs a positive quantity`, and a line above what its
location holds raises `not enough <sku> at <location>`, the wording a transfer
uses. A write-off that raises leaves the stock exactly as it was, whichever
line was at fault. Otherwise every line comes out of the stock at its own
location, and a line marked `damaged` puts the same quantity at `QUARANTINE`.
Add `render_writeoff(writeoff)` in a new file `src/inventory/writeoffs.py`. It
returns the header `Write-off <id> (<reason>)`, then one stock line per line of
the write-off, printed exactly as a receipt prints it, then a last line
`<n> line(s) removed from stock` with the number of lines.

## Why
The warehouse writes off 30 to 50 lines a month on paper, and the ledger learns
of it at the next stocktake. Two counts last quarter were wrong for a month,
and neither had a recorded reason. A paper write-off covers a whole pallet, so
one of them names several skus at several places.

## How I'll know it works
A write-off for `damaged in transit` over two lines, 12 `BOLT-9` in `pcs` at
`A1` marked `damaged` and 4 `SAND` in `kg` at `B1`, applied to a stock of 40
`BOLT-9` at `A1` and 10 `SAND` at `B1`, leaves 28 at `A1`, 12 at `QUARANTINE`,
and 6 at `B1`. The same write-off with 50 on its first line raises
`not enough BOLT-9 at A1` and leaves both quantities as they were. One with no
reason raises `a write-off needs a reason`. `render_writeoff` over those two
lines, for the write-off `W-3`, gives the four lines
`Write-off W-3 (damaged in transit)`, `BOLT-9          12 pcs @A1`,
`SAND             4 kg  @B1`, and `2 line(s) removed from stock`. Tests under
`tests/` pin all of it, and `scripts/run-tests.sh --all` stays green.

## Notes for the loop
- Touches `src/inventory/` and `tests/` only. Independent of in-flight work.
- Not a critical path.
PLAN

# Resolve the test dependency once, so uv.lock is part of the seed commit and
# every later run of the adapter, in any worktree, resolves from the cache.
uv sync --quiet >/dev/null 2>&1 \
    || { echo "uv sync could not build the fixture's environment" >&2; exit 1; }
bash scripts/run-tests.sh --all >/dev/null 2>&1 \
    || { echo "the seeded suite is red, so no run of this scenario would mean anything" >&2; exit 1; }
