"""The driver manifest, with a billable weight per line and a total."""

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


def test_the_manifest_prints_a_billable_weight_per_line_and_a_total():
    assert render_manifest(RUN) == "\n".join(
        [
            "Manifest M-1 | Berlin Sud | 2026-03-02",
            "P-1         ground      2.75 kg  2026-03-05",
            "P-2         air         1.00 kg  2026-03-04",
            "2 parcel(s), 3.75 kg billable",
        ]
    )
