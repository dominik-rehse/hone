"""The counter's offer of a declared value, after the cover rose."""

from depot.quotes import render_quote, suggest_declaring


def parcel(worth_cents):
    return {
        "id": "Q-1",
        "service": "standard",
        "zone": "DE",
        "grams": 2500,
        "worth_cents": worth_cents,
    }


def test_the_counter_offers_a_declared_value_above_the_free_cover():
    assert not suggest_declaring(parcel(100000))
    assert suggest_declaring(parcel(100001))


def test_a_parcel_under_the_free_cover_gets_no_offer():
    assert "Declare a value" not in render_quote(parcel(80000))


def test_a_parcel_over_the_free_cover_gets_the_offer():
    assert "Declare a value" in render_quote(parcel(150000))
