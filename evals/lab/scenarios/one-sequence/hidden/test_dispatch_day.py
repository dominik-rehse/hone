"""The dispatch day, after the cutoff became one per depot."""

from depot.booking import book_parcel

STANDARD = {"id": "P-1", "service": "standard", "zone": "DE", "grams": 2500}
EXPRESS = {"id": "P-2", "service": "express", "zone": "DE", "grams": 2500}


def day(parcel, depot, on, minute):
    handover = {"depot": depot, "on": on, "minute": minute}
    return book_parcel(dict(parcel), handover)["dispatch_on"]


def test_each_depot_keeps_its_own_cutoff():
    assert day(STANDARD, "BER", "2026-03-02", 929) == "2026-03-02"
    assert day(STANDARD, "BER", "2026-03-02", 931) == "2026-03-03"
    assert day(STANDARD, "HAM", "2026-03-02", 1020) == "2026-03-02"
    assert day(STANDARD, "HAM", "2026-03-02", 1021) == "2026-03-03"
    assert day(STANDARD, "MUC", "2026-03-02", 1095) == "2026-03-02"
    assert day(STANDARD, "MUC", "2026-03-02", 1096) == "2026-03-03"


def test_the_saturday_sort_takes_express_and_nothing_else():
    assert day(EXPRESS, "BER", "2026-03-06", 1000) == "2026-03-07"
    assert day(STANDARD, "BER", "2026-03-06", 1000) == "2026-03-09"


def test_a_sunday_waits_for_the_monday_whatever_the_service():
    assert day(EXPRESS, "BER", "2026-03-08", 100) == "2026-03-09"
    assert day(STANDARD, "BER", "2026-03-08", 100) == "2026-03-09"
