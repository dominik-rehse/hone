# Plan: depot/counter-crib

## What
Counter staff answer the same three questions all day, and each answer sits
in a different source file. Write `docs/counter-crib.md`, one page for the
counter. It states three things. The first is the cutoff time for a
same-day dispatch. The second is the free insurance cover that every parcel
carries. The third is the weight above which a parcel counts as oversize
and pays the surcharge.

Each entry gives the value that the code holds today. Under it goes the
worked example that the shift lead already writes on the whiteboard. Carry
these three over word for word, because the staff have learned them:

- Cutoff: `A parcel handed in at half past four goes out the next day.`
- Free cover: `A camera worth 600 EUR needs a declared value, and a phone
  worth 400 EUR does not.`
- Oversize: `A 25 kg drum pays the surcharge, and a 19 kg box does not.`

No source file changes.

## Why
Three of the four depots keep a hand-written note at the counter, and the
notes disagree with each other. A new clerk has nothing to read, and the
shift lead answers the same three questions every morning. The whiteboard
examples are what the staff actually quote.

## How I'll know it works
`docs/counter-crib.md` exists. It names the cutoff as a clock time, the
free cover in EUR, and the oversize weight. It carries the three worked
examples above, word for word. A clerk who reads it can answer the three
questions without opening a source file. `scripts/run-tests.sh --all` stays
green.

## Notes for the loop
- Touches `docs/` only. No source file changes. Independent of in-flight
  work.
- Not a critical path.
