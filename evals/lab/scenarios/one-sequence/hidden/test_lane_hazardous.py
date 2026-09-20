"""The ADR lane and the three refusals that come with it."""

import pytest

from depot.booking import book_parcel

BER = {"depot": "BER", "on": "2026-03-02", "minute": 600}


def parcel(**extra):
    base = {
        "id": "H-1",
        "service": "standard",
        "zone": "DE",
        "grams": 2000,
        "hazardous": True,
        "un_number": "UN1263",
    }
    base.update(extra)
    return base


def test_a_hazardous_parcel_takes_the_adr_lane_and_one_day_more():
    booking = book_parcel(parcel(), BER)
    assert booking["lane"] == "adr"
    assert booking["promised_on"] == "2026-03-06"


def test_a_hazardous_parcel_without_a_un_number_is_refused():
    without = parcel()
    del without["un_number"]
    with pytest.raises(ValueError, match="a hazardous parcel needs a un_number"):
        book_parcel(without, BER)


def test_a_hazardous_parcel_over_the_limit_is_refused():
    with pytest.raises(ValueError, match="a hazardous parcel may not exceed 30000 g"):
        book_parcel(parcel(grams=30001), BER)


def test_a_hazardous_parcel_outside_the_eu_is_refused():
    with pytest.raises(ValueError, match="the network takes no hazardous parcel outside the EU"):
        book_parcel(parcel(zone="WORLD"), BER)
