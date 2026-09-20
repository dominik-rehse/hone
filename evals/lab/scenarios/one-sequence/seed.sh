# One repository that seven Plans pass over, one after the other. The seed
# builds the base only. The driver of run.sh hands each brief over in turn,
# because a session that could read brief 7 would see every trap at once.
#
# Four traps sit across the sequence, and no single brief hints at one.
#
#   Change 2 adds `billable_weight` in `pricing.py`. Change 6 needs the same
#   rounding on the driver manifest, in another module. `dup` and
#   `weight_places` read what the run did with it.
#
#   Change 3 writes a crib sheet for the counter that names three values.
#   Change 5 changes the cutoff time, and change 7 changes the free cover.
#   `docs_true` reads whether a document still states a value that is false.
#
#   Changes 1, 4, 5 and 7 each add a branch to `book_parcel`. Inline they
#   take it from cyclomatic complexity 5 to about 14, and `scb-check` counts
#   a function over 10. `cc_pile` reads that.
#
#   Change 1 records a Decision that the whole network shares one cutoff.
#   Change 5 gives each depot its own, and says nothing about the Decision.
#
# The fixture needs `uv` and `uvx` on PATH: `uv` for the test adapter, `uvx`
# for the structure measure. As in `python-structure`, the base seed installed
# the Node adapter, so this seed removes every Node trace and runs hone's own
# setup.sh again.
command -v uv >/dev/null && command -v uvx >/dev/null \
    || { echo "the one-sequence fixture needs uv and uvx on PATH" >&2; exit 1; }

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
    || { echo "hone's setup.sh failed on the one-sequence fixture" >&2; exit 1; }
grep -q 'uv run pytest' scripts/run-tests.sh \
    || { echo "setup.sh installed no Python test adapter" >&2; exit 1; }
for entry in '.venv/' '__pycache__/' '.pytest_cache/'; do
    grep -qxF "$entry" .gitignore || printf '%s\n' "$entry" >> .gitignore
done

mkdir -p src/depot tests docs/notes

cat > src/depot/__init__.py <<'PY'
"""A parcel depot: what it takes in, what it books, and what it prints."""
PY

cat > src/depot/network.py <<'PY'
"""The depots, the services and the zones that the network serves."""

DEPOTS = {
    "BER": {"name": "Berlin Sud", "bays": 12},
    "HAM": {"name": "Hamburg Hafen", "bays": 8},
    "MUC": {"name": "Munich Ost", "bays": 10},
}

SERVICES = ("standard", "express", "economy")

ZONES = ("DE", "EU", "WORLD")

PROMISED_DAYS = {"standard": 3, "express": 1, "economy": 5}

ZONE_EXTRA_DAYS = {"DE": 0, "EU": 1, "WORLD": 4}

OVERSIZE_GRAMS = 20000


def depot_name(code):
    """The printed name of one depot."""
    if code not in DEPOTS:
        raise ValueError(f"unknown depot {code}")
    return DEPOTS[code]["name"]
PY

cat > src/depot/parcels.py <<'PY'
"""The parcel record, and what makes one usable."""

from depot.network import OVERSIZE_GRAMS, SERVICES, ZONES

REQUIRED = ("id", "service", "zone", "grams")


def validate_parcel(parcel):
    """Give the parcel back, or raise ValueError naming the first fault."""
    for field in REQUIRED:
        if field not in parcel:
            raise ValueError(f"a parcel needs a {field}")
    if parcel["service"] not in SERVICES:
        raise ValueError(f"unknown service {parcel['service']}")
    if parcel["zone"] not in ZONES:
        raise ValueError(f"unknown zone {parcel['zone']}")
    if parcel["grams"] <= 0:
        raise ValueError("a parcel needs a positive weight")
    return parcel


def is_oversize(parcel):
    """Does the parcel go over the limit for a hand parcel?"""
    return parcel["grams"] > OVERSIZE_GRAMS
PY

cat > src/depot/pricing.py <<'PY'
"""What one parcel costs, in cents."""

from depot.parcels import is_oversize

BASE_CENTS = {"DE": 490, "EU": 990, "WORLD": 1890}

SERVICE_UPLIFT_CENTS = {"standard": 0, "express": 600, "economy": -120}

WEIGHT_CENTS_PER_KILO = 180

OVERSIZE_SURCHARGE_CENTS = 450

FREE_COVER_CENTS = 50000


def price_parcel(parcel):
    """The price of one parcel, in whole cents."""
    price = BASE_CENTS[parcel["zone"]] + SERVICE_UPLIFT_CENTS[parcel["service"]]
    kilos = (parcel["grams"] + 999) // 1000
    price += kilos * WEIGHT_CENTS_PER_KILO
    if is_oversize(parcel):
        price += OVERSIZE_SURCHARGE_CENTS
    return price
PY

cat > src/depot/booking.py <<'PY'
"""Turning a handed-over parcel into a booking."""

from datetime import date, timedelta

from depot.network import DEPOTS, PROMISED_DAYS, ZONE_EXTRA_DAYS
from depot.parcels import validate_parcel
from depot.pricing import price_parcel

LANES = {"standard": "ground", "express": "air", "economy": "ground"}


def book_parcel(parcel, handover):
    """Book one parcel and give the booking back.

    `handover` names the depot that took the parcel and the day it took it,
    as an ISO date. The booking carries the parcel, the depot, the lane the
    parcel travels on, its weight, the day the depot dispatches it, the day
    the network promises it, and the price in cents.
    """
    validate_parcel(parcel)
    depot = handover["depot"]
    if depot not in DEPOTS:
        raise ValueError(f"unknown depot {depot}")
    service = parcel["service"]
    lane = LANES[service]
    if parcel.get("fragile"):
        # A fragile parcel never flies. The air lane loads down a chute.
        lane = "ground"
    days = PROMISED_DAYS[service] + ZONE_EXTRA_DAYS[parcel["zone"]]
    dispatch_on = date.fromisoformat(handover["on"])
    return {
        "parcel": parcel["id"],
        "depot": depot,
        "lane": lane,
        "grams": parcel["grams"],
        "dispatch_on": dispatch_on.isoformat(),
        "promised_on": (dispatch_on + timedelta(days=days)).isoformat(),
        "price_cents": price_parcel(parcel),
    }
PY

cat > src/depot/quotes.py <<'PY'
"""What the counter quotes a customer over the desk."""

from depot.pricing import price_parcel

# The counter offers a declared value for a parcel worth more than the free
# cover. The till reads this figure in whole euro, over a wire that carries no
# import, so it is held here and not taken from pricing.py. It has to track
# the free cover: a parcel worth more than the cover should be declared.
SUGGESTED_DECLARE_ABOVE_EUR = 500


def suggest_declaring(parcel):
    """Should the clerk offer a declared value for this parcel?"""
    return parcel.get("worth_cents", 0) > SUGGESTED_DECLARE_ABOVE_EUR * 100


def render_quote(parcel):
    """The slip the clerk hands over the desk."""
    lines = [f"Quote for {parcel['id']}: {price_parcel(parcel) / 100:.2f} EUR"]
    if suggest_declaring(parcel):
        lines.append("Declare a value: this parcel is worth more than the free cover.")
    return "\n".join(lines)
PY

cat > src/depot/manifest.py <<'PY'
"""The list that the driver signs for."""

from depot.network import depot_name


def _manifest_line(booking):
    return f"{booking['parcel']:<12}{booking['lane']:<8}{booking['promised_on']}"


def render_manifest(run):
    """The manifest of one dispatch run."""
    lines = [f"Manifest {run['id']} | {depot_name(run['depot'])} | {run['dispatch_on']}"]
    for booking in run["bookings"]:
        lines.append(_manifest_line(booking))
    lines.append(f"{len(run['bookings'])} parcel(s)")
    return "\n".join(lines)
PY

cat > src/depot/labels.py <<'PY'
"""The sticker that goes on the parcel."""

from depot.network import depot_name
from depot.pricing import FREE_COVER_CENTS


def render_label(booking):
    """Four lines: the parcel, the route, the promise, and the cover."""
    return "\n".join(
        [
            f"** {booking['parcel']} **",
            f"{booking['lane'].upper()} via {depot_name(booking['depot'])}",
            f"due {booking['promised_on']}",
            f"cover {FREE_COVER_CENTS / 100:.2f} EUR",
        ]
    )
PY

cat > tests/test_parcels.py <<'PY'
import pytest

from depot.parcels import is_oversize, validate_parcel


def test_a_full_record_comes_back_unchanged():
    parcel = {"id": "P-1", "service": "standard", "zone": "DE", "grams": 2500}
    assert validate_parcel(parcel) is parcel


def test_a_missing_field_names_itself():
    with pytest.raises(ValueError, match="a parcel needs a zone"):
        validate_parcel({"id": "P-1", "service": "standard", "grams": 100})


def test_an_unknown_service_raises():
    with pytest.raises(ValueError, match="unknown service sameday"):
        validate_parcel({"id": "P-1", "service": "sameday", "zone": "DE", "grams": 100})


def test_a_weight_that_is_not_positive_raises():
    with pytest.raises(ValueError, match="a parcel needs a positive weight"):
        validate_parcel({"id": "P-1", "service": "standard", "zone": "DE", "grams": 0})


def test_oversize_reads_the_counter_limit():
    assert is_oversize({"grams": 20001})
    assert not is_oversize({"grams": 20000})
PY

cat > tests/test_pricing.py <<'PY'
from depot.pricing import price_parcel


def test_a_home_parcel_pays_the_base_rate_and_its_kilos():
    parcel = {"id": "P-1", "service": "standard", "zone": "DE", "grams": 2500}
    assert price_parcel(parcel) == 1030


def test_an_express_parcel_pays_the_service_uplift():
    parcel = {"id": "P-2", "service": "express", "zone": "EU", "grams": 800}
    assert price_parcel(parcel) == 1770


def test_an_oversize_parcel_pays_the_surcharge():
    parcel = {"id": "P-3", "service": "economy", "zone": "WORLD", "grams": 25000}
    assert price_parcel(parcel) == 6720
PY

cat > tests/test_booking.py <<'PY'
import pytest

from depot.booking import book_parcel

BER = {"depot": "BER", "on": "2026-03-02"}


def test_a_standard_parcel_goes_by_ground_and_is_promised_in_three_days():
    parcel = {"id": "P-1", "service": "standard", "zone": "DE", "grams": 2500}
    booking = book_parcel(parcel, BER)
    assert booking["lane"] == "ground"
    assert booking["dispatch_on"] == "2026-03-02"
    assert booking["promised_on"] == "2026-03-05"
    assert booking["price_cents"] == 1030


def test_an_express_parcel_flies_and_a_far_zone_adds_days():
    parcel = {"id": "P-2", "service": "express", "zone": "EU", "grams": 800}
    booking = book_parcel(parcel, BER)
    assert booking["lane"] == "air"
    assert booking["promised_on"] == "2026-03-04"


def test_a_fragile_parcel_never_flies():
    parcel = {"id": "P-3", "service": "express", "zone": "EU", "grams": 800, "fragile": True}
    assert book_parcel(parcel, BER)["lane"] == "ground"


def test_the_booking_carries_the_weight():
    parcel = {"id": "P-4", "service": "economy", "zone": "WORLD", "grams": 25000}
    assert book_parcel(parcel, BER)["grams"] == 25000


def test_an_unknown_depot_raises():
    parcel = {"id": "P-5", "service": "standard", "zone": "DE", "grams": 100}
    with pytest.raises(ValueError, match="unknown depot KLN"):
        book_parcel(parcel, {"depot": "KLN", "on": "2026-03-02"})
PY

cat > tests/test_manifest.py <<'PY'
from depot.manifest import render_manifest

RUN = {
    "id": "M-1",
    "depot": "BER",
    "dispatch_on": "2026-03-02",
    "bookings": [
        {"parcel": "P-1", "lane": "ground", "grams": 2501, "promised_on": "2026-03-05"},
        {"parcel": "P-2", "lane": "air", "grams": 800, "promised_on": "2026-03-04"},
    ],
}


def test_the_manifest_heads_with_the_run_and_ends_with_the_count():
    assert render_manifest(RUN) == "\n".join(
        [
            "Manifest M-1 | Berlin Sud | 2026-03-02",
            "P-1         ground  2026-03-05",
            "P-2         air     2026-03-04",
            "2 parcel(s)",
        ]
    )
PY

cat > tests/test_quotes.py <<'PY'
from depot.quotes import render_quote, suggest_declaring


def test_a_parcel_under_the_suggestion_gets_one_line():
    parcel = {"id": "P-1", "service": "standard", "zone": "DE", "grams": 2500, "worth_cents": 40000}
    assert not suggest_declaring(parcel)
    assert render_quote(parcel).splitlines()[0].startswith("Quote for P-1: ")
    assert len(render_quote(parcel).splitlines()) == 1


def test_a_parcel_over_the_suggestion_gets_the_offer():
    parcel = {"id": "P-2", "service": "standard", "zone": "DE", "grams": 2500, "worth_cents": 80000}
    assert suggest_declaring(parcel)
    assert "Declare a value" in render_quote(parcel)
PY

cat > tests/test_labels.py <<'PY'
from depot.labels import render_label


def test_the_label_names_the_route_the_promise_and_the_cover():
    booking = {"parcel": "P-1", "depot": "BER", "lane": "ground", "promised_on": "2026-03-05"}
    assert render_label(booking) == "\n".join(
        [
            "** P-1 **",
            "GROUND via Berlin Sud",
            "due 2026-03-05",
            "cover 500.00 EUR",
        ]
    )
PY

cat > docs/notes/depot.md <<'MD'
# depot

Governs: `src/depot/`

Map: `network.py` holds the depots, the services and the zones. `parcels.py`
says what a parcel record must carry. `pricing.py` prices one parcel.
`booking.py` turns a handed-over parcel into a booking. `quotes.py` is what
the counter reads out. `manifest.py` and `labels.py` render the two
documents that a depot prints.

Invariant: a weight is a whole number of grams everywhere but on a printed
document.
MD

# Resolve the test dependency once, so uv.lock is part of the seed commit and
# every later run of the adapter, in any worktree, resolves from the cache.
uv sync --quiet >/dev/null 2>&1 \
    || { echo "uv sync could not build the fixture's environment" >&2; exit 1; }
bash scripts/run-tests.sh --all >/dev/null 2>&1 \
    || { echo "the seeded suite is red, so no run of this scenario would mean anything" >&2; exit 1; }
