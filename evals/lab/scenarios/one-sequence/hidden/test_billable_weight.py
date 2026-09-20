"""The billable weight, wherever the sequence left the helper."""

import importlib
import pkgutil

import pytest

import depot
from depot.pricing import price_parcel


def billable_weight():
    """The helper, whichever module of `depot` holds it at the end."""
    for module in pkgutil.iter_modules(depot.__path__):
        found = getattr(importlib.import_module(f"depot.{module.name}"), "billable_weight", None)
        if found is not None:
            return found
    raise AssertionError("no module of depot defines billable_weight")


def test_the_weight_rounds_up_in_steps_of_250_grams():
    weigh = billable_weight()
    assert weigh(1) == 1000
    assert weigh(1000) == 1000
    assert weigh(1001) == 1250
    assert weigh(2500) == 2500
    assert weigh(2501) == 2750


def test_a_weight_that_is_not_positive_raises():
    with pytest.raises(ValueError, match="a parcel needs a positive weight"):
        billable_weight()(0)


def test_the_price_bills_the_billable_weight():
    assert price_parcel({"service": "standard", "zone": "DE", "grams": 2501}) == 985
    assert price_parcel({"service": "standard", "zone": "DE", "grams": 100}) == 670
    assert price_parcel({"service": "economy", "zone": "WORLD", "grams": 25100}) == 6765
