"""The secure lane, and the cover that the sequence raised."""

import pytest

from depot.booking import book_parcel
from depot.labels import render_label

BER = {"depot": "BER", "on": "2026-03-02", "minute": 600}


def parcel(service="standard", **extra):
    base = {"id": "S-1", "service": service, "zone": "DE", "grams": 2500}
    base.update(extra)
    return base


def test_a_declared_value_at_the_free_cover_books_as_before():
    booking = book_parcel(parcel(declared_cents=100000), BER)
    assert booking["lane"] == "ground"
    assert booking["promised_on"] == "2026-03-05"


def test_a_declared_value_above_the_free_cover_takes_the_secure_lane():
    booking = book_parcel(parcel(declared_cents=100001), BER)
    assert booking["lane"] == "secure"
    assert booking["promised_on"] == "2026-03-06"


def test_economy_carries_no_cover_above_the_free_cover():
    with pytest.raises(ValueError, match="economy carries no cover above the free cover"):
        book_parcel(parcel(service="economy", declared_cents=100001), BER)


def test_the_label_prints_the_raised_cover():
    assert "cover 1000.00 EUR" in render_label(book_parcel(parcel(), BER))
