"""The lanes the base fixture already had, as the sequence leaves them."""

from depot.booking import book_parcel

BER = {"depot": "BER", "on": "2026-03-02", "minute": 600}


def test_a_standard_parcel_goes_by_ground():
    parcel = {"id": "P-1", "service": "standard", "zone": "DE", "grams": 2500}
    assert book_parcel(parcel, BER)["lane"] == "ground"


def test_an_express_parcel_flies():
    parcel = {"id": "P-2", "service": "express", "zone": "EU", "grams": 800}
    assert book_parcel(parcel, BER)["lane"] == "air"


def test_a_fragile_parcel_never_flies():
    parcel = {"id": "P-3", "service": "express", "zone": "EU", "grams": 800, "fragile": True}
    assert book_parcel(parcel, BER)["lane"] == "ground"


def test_an_economy_parcel_goes_by_ground():
    parcel = {"id": "P-4", "service": "economy", "zone": "WORLD", "grams": 1200}
    assert book_parcel(parcel, BER)["lane"] == "ground"


def test_the_booking_carries_the_weight_of_its_parcel():
    parcel = {"id": "P-5", "service": "standard", "zone": "DE", "grams": 2500}
    assert book_parcel(parcel, BER)["grams"] == 2500
