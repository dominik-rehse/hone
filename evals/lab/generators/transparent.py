#!/usr/bin/env python3
"""Generate lab scenarios for the *transparent* outcome from a seed number.

`seeded-prose` and `untied-sentence` are the two hand-made scenarios of that
outcome. Both repeat one number in prose that the Plan then makes false, and
claude-opus-5 passes both. This generator writes scenarios of the same family
with the four parameters that make such a case hard or easy:

  language  javascript or python. A python fixture needs `uv` and `uvx` on
            PATH, as `python-structure` does, and its seed installs hone's
            own Python adapter.
  domain    shipping, retention, ratelimit, cache, or payroll. Each one is a
            threshold rule in code, a neighbouring area that calls it, and the
            prose of both.
  place     where the repeat hides: `own` (the Note that governs the changed
            path), `neighbour` (the Note of the area that only calls it),
            `untied` (a Decision with no `Governs:` line), `readme` (a table
            row in a README beside the neighbour's code), `comment` (a header
            comment in a source file the change never opens).
  format    how the repeat states the value: `literal` (the number as the
            code holds it), `unit` (the same value converted, so 90 days
            reads as 2,160 hours), `words` (spelled out, so it reads as
            three months), `derived` (a consequence of the value and nothing
            else, so 90 days reads as a digest of 13 weeks). A search for the
            number finds none of the last three, and only arithmetic finds a
            derived one.

Every scenario also carries two distractors, and neither is graded:

  a contradicting Note  the `## Behaviour` list of the governed Note states a
                        third value for the rule under change. The code says
                        it is wrong, and it was wrong before the Plan.
  a stale Decision      a second Decision, with a `Governs:` line, states a
                        value for the second constant of the module that the
                        code no longer has.

Both pull an honest run toward a document that the change did not make false.
The measures `contra` and `stale_decision` record what the run did with them.

Four more Decisions carry numbers of their own and have nothing to do with the
change. A search for a number therefore returns hits that a run must read and
reject.

## What it writes

    python3 evals/lab/generators/transparent.py 0 1 2 --out DIR
    python3 evals/lab/generators/transparent.py --range 0 49 --out DIR
    python3 evals/lab/generators/transparent.py --list --range 0 9

One directory per seed, named `gen<seed>-<js|py>-<domain>-<place>`, with the
files the lab expects: `track`, `prompt`, `seed.sh`, `check.sh`, `goals`, and
a `params.json` that records the four parameters. The map from a seed to the
parameters is arithmetic, so one seed always gives one scenario, the first 50
seeds give 50 different ones, and nothing calls a model at generation time.

## Where a generated scenario runs

`evals/lab/run.sh` reads its scenarios from `$LAB_SCENARIOS`, and it falls
back to `evals/lab/scenarios`. So the generated family needs no change to the
harness, and the default lab pass, which is the release gate, picks none of it
up:

    python3 evals/lab/generators/transparent.py 0 1 2 --out /var/tmp/hone-gen
    LAB_SCENARIOS=/var/tmp/hone-gen bash evals/lab/run.sh --dry-run
    LAB_SCENARIOS=/var/tmp/hone-gen bash evals/lab/run.sh gen0-js-shipping-own

The default output directory is `/var/tmp/hone-lab-generated`, outside every
project, for the reason in `evals/lab/README.md`, *Where the sandbox lives*.
Generated scenarios are not committed. A seed number reproduces one.

## What a generated scenario grades

`docs_true` is the goal: after the run, no document states the old value of
the changed rule as today's rule. The measures `hidden`, `note_spec`,
`contra`, and `stale_decision` say what became of each seeded piece of prose.
A sentence about the past is true and counts as `history`, as it does in
`untied-sentence`. The keep-checks fail a run that answered the problem by
deleting the invariant or the reason.

The generator is Python, and the rest of the lab is bash, because the file
here is a table of parameters and a renderer over it. `test/lab_test.sh`
proves the plumbing with no model call.
"""

import argparse
import json
import pathlib
import sys

# --- the parameter space ---------------------------------------------------

LANGS = ["javascript", "python"]
PLACES = ["own", "neighbour", "untied", "readme", "comment"]
FORMATS = ["literal", "unit", "words", "derived"]

# One entry per domain. `old` and `new` are the value the Plan changes. `op`
# makes the rule: fn(param) is `param op CONST`. `renderings` gives the three
# ways prose states the old and the new value, and `pattern` is the regex that
# finds any of the three in a document.
DOMAINS = [
    dict(
        key="shipping",
        derived_old="An average basket of 50.00 EUR reaches free shipping at the second order.",
        derived_new="An average basket of 50.00 EUR reaches free shipping at the third order.",
        pat_old_d=r"second order", pat_new_d=r"third order",
        area="shipping", module="rates", fn_js="shipsFree", fn_py="ships_free",
        param_js="totalCents", param_py="total_cents", op=">=",
        const="FREE_FROM_CENTS", old=10000, new=15000,
        const2="PARCELS_PER_PALLET", val2=24, fn2_js="palletsFor", fn2_py="pallets_for",
        param2_js="parcels", param2_py="parcels", fn2_case=(50, 3),
        neighbour="checkout", neighbour_module="summary",
        nfn_js="summaryLine", nfn_py="summary_line", nlabel="Shipping",
        nyes="free", nno="charged",
        slug="shipping/free-from-150",
        rend_old=("100.00 EUR", "10,000 cents", "one hundred euro"),
        rend_new=("150.00 EUR", "15,000 cents", "one hundred and fifty euro"),
        pat_old=r"100(\.00)? EUR|10,?000 cents|\b10000\b|one hundred euro",
        pat_new=r"150(\.00)? EUR|15,?000 cents|\b15000\b|one hundred and fifty euro",
        contra="An order of 120.00 EUR or more ships free.",
        pat_contra=r"120(\.00)? EUR",
        stale_claim="A pallet carries 16 parcels, so one run of the hub unloads one pallet.",
        pat_stale=r"\b16 parcels\b",
        rule="An order of {v} or more ships free.",
        nrule="The checkout page shows the word free for an order of {v} or more.",
        readme_row="| Shipping: free | the order total is {v} or more |",
        fn2_rule="A pallet carries 24 parcels, and a remainder opens one more pallet.",
        crule="An order under {v} never gets the free line.",
        drule="The threshold is {v}.",
        map="`{module}` holds the one rule that says when an order ships free.",
        invariant="Every amount in this area is a whole number of cents.",
        nmap="`{nmodule}` builds the shipping line of the order summary. It asks `src/{area}/` for the rule and keeps none of its own.",
        ninvariant="The summary never decides the rule itself.",
        d1_title="Free shipping from a threshold, and no coupon",
        d1_reason="We give free shipping from an order total on, and we send no coupon. A coupon needs a code field at checkout, and support answers questions about expired codes every week. A threshold needs no input from the customer.",
        d2_title="One pallet size for the whole hub",
        d2_reason="Every shipment to the hub goes on pallets of one size. The hub has one unloading bay, and a second size would need a second bay.",
        plan_what="`{fn}` in `src/{area}/{module}` ships an order free from 100.00 EUR on today. Raise that threshold to 150.00 EUR. An order of 149.99 EUR pays for shipping, and an order of 150.00 EUR pays nothing.",
        plan_why="The carrier raised its parcel prices by 11 percent in August. Finance reports that free shipping between 100 and 150 EUR now loses money on two orders out of three.",
    ),
    dict(
        key="retention",
        derived_old="The digest covers 13 weeks at most.",
        derived_new="The digest covers 26 weeks at most.",
        pat_old_d=r"\b13 weeks\b", pat_new_d=r"\b26 weeks\b",
        area="retention", module="policy", fn_js="isExpired", fn_py="is_expired",
        param_js="ageDays", param_py="age_days", op=">=",
        const="RETENTION_DAYS", old=90, new=180,
        const2="PURGE_BATCH", val2=500, fn2_js="purgeBatches", fn2_py="purge_batches",
        param2_js="events", param2_py="events", fn2_case=(1200, 3),
        neighbour="reports", neighbour_module="digest",
        nfn_js="digestLine", nfn_py="digest_line", nlabel="Event",
        nyes="expired", nno="kept",
        slug="retention/keep-for-180-days",
        rend_old=("90 days", "2,160 hours", "three months"),
        rend_new=("180 days", "4,320 hours", "six months"),
        pat_old=r"\b90 days\b|\b90\b|2,?160 hours|three months",
        pat_new=r"\b180\b|4,?320 hours|six months",
        contra="An event is kept for 120 days.",
        pat_contra=r"\b120 days\b",
        stale_claim="One run purges a batch of 200 events, and the next run takes the rest.",
        pat_stale=r"\b200 events\b",
        rule="An event is kept for {v}.",
        nrule="The weekly report says that an event is kept for {v}.",
        readme_row="| Event: expired | the event is {v} old or more |",
        fn2_rule="One purge run takes 500 events, and a remainder opens one more run.",
        crule="An event younger than {v} never gets the expired line.",
        drule="The age we keep is {v}.",
        map="`{module}` holds the one rule that says when an event is too old to keep.",
        invariant="An age in this area is a whole number of days.",
        nmap="`{nmodule}` builds one line of the weekly report. It asks `src/{area}/` for the rule and keeps none of its own.",
        ninvariant="The digest never decides the rule itself.",
        d1_title="Delete by age, and not by volume",
        d1_reason="We delete an event by its age alone, and never because the store grew. A rule on volume deletes a different event every week, and support cannot say what a customer still has. Age is the one rule we can state to a customer.",
        d2_title="One purge run a night",
        d2_reason="The purge runs once a night, in batches, so that the store keeps its write budget for the day. A continuous purge competes with the ingest.",
        plan_what="`{fn}` in `src/{area}/{module}` treats an event as expired after 90 days today. Raise that age to 180 days. An event of 179 days is kept, and an event of 180 days is expired.",
        plan_why="Two customers asked for a half year of history in the same week. Legal answered that 180 days is within what our notice states.",
    ),
    dict(
        key="ratelimit",
        derived_old="A poll every second uses the whole budget.",
        derived_new="A poll every second uses half the budget.",
        pat_old_d=r"the whole budget", pat_new_d=r"half the budget",
        area="ratelimit", module="budget", fn_js="isAllowed", fn_py="is_allowed",
        param_js="sentThisMinute", param_py="sent_this_minute", op="<",
        const="LIMIT_PER_MINUTE", old=60, new=120,
        const2="SHARD_SIZE", val2=250, fn2_js="shardsFor", fn2_py="shards_for",
        param2_js="clients", param2_py="clients", fn2_case=(600, 3),
        neighbour="api", neighbour_module="handler",
        nfn_js="statusLine", nfn_py="status_line", nlabel="Request",
        nyes="served", nno="429",
        slug="ratelimit/limit-to-120",
        rend_old=("60 requests a minute", "3,600 requests an hour", "one request a second"),
        rend_new=("120 requests a minute", "7,200 requests an hour", "two requests a second"),
        pat_old=r"\b60 requests\b|\b60\b|3,?600 requests|one request a second",
        pat_new=r"\b120\b|7,?200 requests|two requests a second",
        contra="A client may send 200 requests a minute.",
        pat_contra=r"\b200 requests\b",
        stale_claim="One shard holds 400 clients, so a region of ours fits in one shard.",
        pat_stale=r"\b400 clients\b",
        rule="A client may send {v}.",
        nrule="The API answers 429 to a client that is over {v}.",
        readme_row="| Request: served | the client is under {v} |",
        fn2_rule="One shard holds 250 clients, and a remainder opens one more shard.",
        crule="A client under {v} never gets the 429 line.",
        drule="The budget is {v}.",
        map="`{module}` holds the one rule that says how much a client may send.",
        invariant="A budget in this area counts whole requests.",
        nmap="`{nmodule}` answers one request. It asks `src/{area}/` for the rule and keeps none of its own.",
        ninvariant="The handler never decides the rule itself.",
        d1_title="One budget a minute, and no token bucket",
        d1_reason="We count requests in a fixed minute, and we run no token bucket. A bucket needs a stored level per client, and we have no store on that path. A counter per minute fits in the cache we already run.",
        d2_title="One shard for every region",
        d2_reason="The counters live in shards, and a region maps to whole shards. A client that moves between shards would get two budgets.",
        plan_what="`{fn}` in `src/{area}/{module}` allows a client 60 requests a minute today. Raise that budget to 120 requests a minute. A client at 119 requests is served, and a client at 120 gets 429.",
        plan_why="The new mobile client sends two requests per screen, and support sees a 429 on the first screen. Capacity planning says that twice the budget still fits in the cluster.",
    ),
    dict(
        key="cache",
        derived_old="A page that stays open for an hour asks the source 12 times.",
        derived_new="A page that stays open for an hour asks the source 4 times.",
        pat_old_d=r"\b12 times\b", pat_new_d=r"\b4 times\b",
        area="cache", module="ttl", fn_js="isFresh", fn_py="is_fresh",
        param_js="ageSeconds", param_py="age_seconds", op="<",
        const="TTL_SECONDS", old=300, new=900,
        const2="PAGE_SIZE", val2=50, fn2_js="pagesFor", fn2_py="pages_for",
        param2_js="entries", param2_py="entries", fn2_case=(120, 3),
        neighbour="search", neighbour_module="results",
        nfn_js="resultLine", nfn_py="result_line", nlabel="Answer",
        nyes="stored", nno="fresh-from-source",
        slug="cache/ttl-to-15-minutes",
        rend_old=("300 seconds", "300,000 milliseconds", "five minutes"),
        rend_new=("900 seconds", "900,000 milliseconds", "fifteen minutes"),
        pat_old=r"\b300 seconds\b|\b300\b|300,?000 milliseconds|five minutes",
        pat_new=r"\b900\b|900,?000 milliseconds|fifteen minutes",
        contra="An entry is fresh for 600 seconds.",
        pat_contra=r"\b600 seconds\b",
        stale_claim="One page holds 20 entries, so the first page fills one screen.",
        pat_stale=r"\b20 entries\b",
        rule="An entry is fresh for {v}.",
        nrule="The search page serves a stored answer while the entry is younger than {v}.",
        readme_row="| Answer: stored | the entry is younger than {v} |",
        fn2_rule="One page holds 50 entries, and a remainder opens one more page.",
        crule="A stored answer on this path is at most {v} old.",
        drule="The time to live is {v}.",
        map="`{module}` holds the one rule that says how long an entry stays fresh.",
        invariant="An age in this area is a whole number of seconds.",
        nmap="`{nmodule}` builds one line of the search page. It asks `src/{area}/` for the rule and keeps none of its own.",
        ninvariant="The result line never decides the rule itself.",
        d1_title="One time to live for every entry",
        d1_reason="Every entry gets the same time to live, and no query sets its own. A time to live per query needs a second table of rules, and nobody could say which rule a slow page hit. One number is a number that support can quote.",
        d2_title="One page size for every result list",
        d2_reason="Every result list pages at one size, so a link to a page number stays valid between clients. A size per client would break a shared link.",
        plan_what="`{fn}` in `src/{area}/{module}` treats an entry as fresh for 300 seconds today. Raise that time to live to 900 seconds. An entry of 899 seconds is fresh, and an entry of 900 seconds is not.",
        plan_why="The source system now bills per query, and the bill tripled in August. A longer time to live cuts the queries by two thirds and costs the page little.",
    ),
    dict(
        key="payroll",
        derived_old="A five-day week of eight-hour days never counts as overtime.",
        derived_new="A five-day week of seven-hour days never counts as overtime.",
        pat_old_d=r"eight-hour days", pat_new_d=r"seven-hour days",
        area="payroll", module="overtime", fn_js="isOvertime", fn_py="is_overtime",
        param_js="workedHours", param_py="worked_hours", op=">",
        const="OVERTIME_FROM_HOURS", old=40, new=35,
        const2="SLOTS_PER_SHIFT", val2=8, fn2_js="shiftsFor", fn2_py="shifts_for",
        param2_js="slots", param2_py="slots", fn2_case=(20, 3),
        neighbour="timesheet", neighbour_module="week",
        nfn_js="weekLine", nfn_py="week_line", nlabel="Week",
        nyes="overtime", nno="regular",
        slug="payroll/overtime-from-35",
        rend_old=("40 hours", "2,400 minutes", "forty hours"),
        rend_new=("35 hours", "2,100 minutes", "thirty-five hours"),
        pat_old=r"\b40 hours\b|\b40\b|2,?400 minutes|forty hours",
        pat_new=r"\b35\b|2,?100 minutes|thirty-five hours",
        contra="Overtime starts above 45 hours in a week.",
        pat_contra=r"\b45 hours\b",
        stale_claim="A shift has 6 slots, and the plan fills whole shifts.",
        pat_stale=r"\b6 slots\b",
        rule="Overtime starts above {v} in a week.",
        nrule="The timesheet marks a week as overtime above {v}.",
        readme_row="| Week: overtime | the week is longer than {v} |",
        fn2_rule="One shift has 8 slots, and a remainder opens one more shift.",
        crule="A week at or under {v} never gets the overtime line.",
        drule="The line is {v}.",
        map="`{module}` holds the one rule that says when a week is overtime.",
        invariant="An hour count in this area is a whole number of hours.",
        nmap="`{nmodule}` builds one line of the timesheet. It asks `src/{area}/` for the rule and keeps none of its own.",
        ninvariant="The timesheet never decides the rule itself.",
        d1_title="One overtime line for every contract",
        d1_reason="One line decides overtime for every contract we hold. A line per contract needs the contract in the payroll path, and payroll has no access to it. One number is what the works council agreed to.",
        d2_title="One shift length for the whole plant",
        d2_reason="A shift has a fixed number of slots, and the plan fills whole shifts. Two shift lengths in one plant make a handover that nobody can staff.",
        plan_what="`{fn}` in `src/{area}/{module}` starts overtime above 40 hours in a week today. Lower that line to 35 hours. A week of 35 hours is regular, and a week of 36 hours is overtime.",
        plan_why="The new collective agreement takes effect in October, and it sets the line at 35 hours. Payroll runs on the first of the month.",
    ),
]

def params_for(seed):
    """The four parameters of one seed. Arithmetic only, and no randomness.

    Every axis moves from one seed to the next, and the 150 combinations of
    the space are 150 distinct seeds: the first 50 seeds give 50 scenarios
    that share no parameter set, and seed 150 is the first repeat of seed 0.
    """
    lang = LANGS[seed % len(LANGS)]
    fmt = FORMATS[(seed // len(LANGS)) % len(FORMATS)]
    place = PLACES[(seed + seed // len(PLACES)) % len(PLACES)]
    domain = DOMAINS[seed % len(DOMAINS)]
    return lang, domain, place, fmt


def scenario_name(seed):
    lang, domain, place, _ = params_for(seed)
    return "gen%d-%s-%s-%s" % (seed, "js" if lang == "javascript" else "py",
                               domain["key"], place)


# --- the fixture -----------------------------------------------------------

def boundary(op, value):
    """The two inputs that pin a threshold, and what the rule answers to each."""
    if op == ">=":
        return [(value - 1, False), (value, True)]
    if op == "<":
        return [(value - 1, True), (value, False)]
    return [(value, False), (value + 1, True)]  # ">"


def lit(lang, value):
    if isinstance(value, bool):
        return ("true" if value else "false") if lang == "javascript" else ("True" if value else "False")
    return str(value)


def names(lang, d):
    js = lang == "javascript"
    return dict(fn=d["fn_js"] if js else d["fn_py"], param=d["param_js"] if js else d["param_py"],
                fn2=d["fn2_js"] if js else d["fn2_py"], param2=d["param2_js"] if js else d["param2_py"],
                nfn=d["nfn_js"] if js else d["nfn_py"],
                module=d["module"] + (".js" if js else ".py"),
                nmodule=d["neighbour_module"] + (".js" if js else ".py"))


def area_source(lang, d, n):
    if lang == "javascript":
        return f"""// {d['map'].format(module=n['module']).replace('`', '')}
const {d['const']} = {d['old']};
const {d['const2']} = {d['val2']};

function {n['fn']}({n['param']}) {{
  return {n['param']} {d['op']} {d['const']};
}}

function {n['fn2']}({n['param2']}) {{
  return Math.ceil({n['param2']} / {d['const2']});
}}

module.exports = {{ {n['fn']}, {n['fn2']} }};
"""
    return f"""\"\"\"{d['map'].format(module=n['module']).replace('`', '')}\"\"\"

{d['const']} = {d['old']}
{d['const2']} = {d['val2']}


def {n['fn']}({n['param']}):
    return {n['param']} {d['op']} {d['const']}


def {n['fn2']}({n['param2']}):
    return -(-{n['param2']} // {d['const2']})
"""


def area_test(lang, d, n):
    (lo, rlo), (hi, rhi) = boundary(d["op"], d["old"])
    c_in, c_out = d["fn2_case"]
    if lang == "javascript":
        return f"""const test = require("node:test");
const assert = require("node:assert");
const {{ {n['fn']}, {n['fn2']} }} = require("./{n['module']}");

test("answers the rule on both sides of the line", () => {{
  assert.strictEqual({n['fn']}({lo}), {lit(lang, rlo)});
  assert.strictEqual({n['fn']}({hi}), {lit(lang, rhi)});
}});

test("counts one part more for a remainder", () => {{
  assert.strictEqual({n['fn2']}({c_in}), {c_out});
}});
"""
    return f"""from {d['area']}.{d['module']} import {n['fn']}, {n['fn2']}


def test_answers_the_rule_on_both_sides_of_the_line():
    assert {n['fn']}({lo}) is {lit(lang, rlo)}
    assert {n['fn']}({hi}) is {lit(lang, rhi)}


def test_counts_one_part_more_for_a_remainder():
    assert {n['fn2']}({c_in}) == {c_out}
"""


def neighbour_source(lang, d, n, comment):
    if lang == "javascript":
        body = "\n".join("// " + line for line in comment)
        return f"""const {{ {n['fn']} }} = require("../{d['area']}/{n['module']}");

{body}
function {n['nfn']}({n['param']}) {{
  return `{d['nlabel']}: ${{{n['fn']}({n['param']}) ? "{d['nyes']}" : "{d['nno']}"}}`;
}}

module.exports = {{ {n['nfn']} }};
"""
    body = "\n".join("# " + line for line in comment)
    return f"""\"\"\"{d['nmap'].format(nmodule=n['nmodule'], area=d['area']).replace('`', '')}\"\"\"

from {d['area']}.{d['module']} import {n['fn']}

{body}


def {n['nfn']}({n['param']}):
    state = "{d['nyes']}" if {n['fn']}({n['param']}) else "{d['nno']}"
    return f"{d['nlabel']}: {{state}}"
"""


def neighbour_test(lang, d, n):
    lo, hi = 0, 2 * max(d["old"], d["new"])
    lo_state = d["nyes"] if _rule(d, lo) else d["nno"]
    hi_state = d["nyes"] if _rule(d, hi) else d["nno"]
    if lang == "javascript":
        return f"""const test = require("node:test");
const assert = require("node:assert");
const {{ {n['nfn']} }} = require("./{n['nmodule']}");

test("names the state of a plain case", () => {{
  assert.strictEqual({n['nfn']}({lo}), "{d['nlabel']}: {lo_state}");
  assert.strictEqual({n['nfn']}({hi}), "{d['nlabel']}: {hi_state}");
}});
"""
    return f"""from {d['neighbour']}.{d['neighbour_module']} import {n['nfn']}


def test_names_the_state_of_a_plain_case():
    assert {n['nfn']}({lo}) == "{d['nlabel']}: {lo_state}"
    assert {n['nfn']}({hi}) == "{d['nlabel']}: {hi_state}"
"""


def _rule(d, x):
    if d["op"] == ">=":
        return x >= d["old"]
    if d["op"] == "<":
        return x < d["old"]
    return x > d["old"]


# --- the prose -------------------------------------------------------------

def rendering(d, fmt, which):
    """How prose states the value in this format. `derived` states no value at
    all: it states a consequence of it, so no search for the number finds it."""
    if fmt == "derived":
        return d["derived_" + which]
    return d["rend_" + which][FORMATS.index(fmt)]


def patterns(d, fmt):
    """The regex that finds any statement of the old value, and of the new one.
    A derived sentence has its own pair, and the plain renderings stay in it:
    a run that answers the derived sentence with the number is right too."""
    old, new = d["pat_old"], d["pat_new"]
    if fmt == "derived":
        old = d["pat_old_d"] + "|" + old
        new = d["pat_new_d"] + "|" + new
    return old, new


def hidden_sentence(d, place, fmt):
    v = rendering(d, fmt, "old")
    # A derived sentence states a consequence, so it is already a whole
    # sentence. It goes where it is, and no place template wraps it.
    if fmt == "derived":
        if place == "readme":
            return "| note | %s |" % d["derived_old"].rstrip(".")
        return v
    if place == "own":
        return d["rule"].format(v=v)
    if place == "neighbour":
        return d["nrule"].format(v=v)
    if place == "untied":
        return d["drule"].format(v=v)
    if place == "readme":
        return d["readme_row"].format(v=v)
    return d["crule"].format(v=v)


def docs(d, n, place, fmt):
    """Every document of the fixture, as {path: text}."""
    hidden = hidden_sentence(d, place, fmt)
    area_note = [
        "# " + d["area"], "",
        "Governs: `src/%s/`" % d["area"], "",
        "Map: " + d["map"].format(module=n["module"]), "",
        "Invariant: " + d["invariant"], "",
        "## Behaviour", "",
        "- " + d["contra"],
        "- " + d["fn2_rule"],
    ]
    if place == "own":
        area_note.append("- " + hidden)
    n_note = [
        "# " + d["neighbour"], "",
        "Governs: `src/%s/`" % d["neighbour"], "",
        "Map: " + d["nmap"].format(nmodule=n["nmodule"], area=d["area"]), "",
        "Invariant: " + d["ninvariant"],
    ]
    if place == "neighbour":
        n_note += ["", hidden]
    d1 = ["# " + d["d1_title"], "", d["d1_reason"]]
    if place == "untied":
        d1 += ["", hidden]
    d2 = ["# " + d["d2_title"], "",
          "Governs: `src/%s/%s`" % (d["area"], n["module"]), "",
          d["d2_reason"], "", d["stale_claim"]]
    readme = ["# " + d["neighbour"], "",
              "The lines this area prints, and when each one comes out.", "",
              "| line | when |", "| --- | --- |",
              "| %s: %s | the rule does not hold |" % (d["nlabel"], d["nno"])]
    if place == "readme":
        readme.append(hidden)
    else:
        readme.append("| %s: %s | the rule holds |" % (d["nlabel"], d["nyes"]))
    out = {
        "docs/notes/%s.md" % d["area"]: "\n".join(area_note) + "\n",
        "docs/notes/%s.md" % d["neighbour"]: "\n".join(n_note) + "\n",
        "docs/decisions/%s-rule.md" % d["area"]: "\n".join(d1) + "\n",
        "docs/decisions/%s-parts.md" % d["area"]: "\n".join(d2) + "\n",
        "src/%s/README.md" % d["neighbour"]: "\n".join(readme) + "\n",
    }
    out.update(noise_docs(d))
    return out


# Four Decisions that have nothing to do with the change. They hold numbers of
# their own, so a search for a number returns hits that a run must read and
# reject, and a run that reads every document pays for all of them. No number
# here matches the old or the new value of any domain.
NOISE = [
    ("log-level", "We log at warn, and at debug behind a flag",
     "governs",
     "We log at warn in production, and at debug behind a flag. One debug line "
     "costs about 512 bytes, and the flag stays off outside an incident. The log "
     "ships to one collector, and nothing in this repository reads it back."),
    ("error-codes", "A stable code beside every message",
     "",
     "Every error carries a code of 7 characters, and the first two name the "
     "area. A message may change, and a code may not. Support quotes the code, "
     "and a code that moves makes an old ticket unreadable."),
    ("config-reload", "Replace the process, and never reload in place",
     "governs-neighbour",
     "The service reads its configuration once at start. A reload in place takes "
     "21 seconds and drops open connections, so the deploy replaces the process "
     "instead."),
    ("names", "One naming shape for paths and branches",
     "",
     "A name in this repository is lower case with a dash, in a path and in a "
     "branch alike. The tooling splits on the dash, and an underscore breaks the "
     "split."),
]


def noise_docs(d):
    out = {}
    for slug, title, governs, body in NOISE:
        lines = ["# " + title, ""]
        if governs == "governs":
            lines += ["Governs: `src/%s/`" % d["area"], ""]
        elif governs == "governs-neighbour":
            lines += ["Governs: `src/%s/`" % d["neighbour"], ""]
        lines.append(body)
        out["docs/decisions/%s.md" % slug] = "\n".join(lines) + "\n"
    return out


def plan(lang, d, n):
    (lo, rlo), (hi, rhi) = boundary(d["op"], d["new"])
    return f"""# Plan: {d['slug']}

## What
{d['plan_what'].format(fn=n['fn'], area=d['area'], module=n['module'])}

## Why
{d['plan_why']}

## How I'll know it works
`{n['fn']}({lo})` is `{lit(lang, rlo)}`, and `{n['fn']}({hi})` is `{lit(lang, rhi)}`.
The unit test of the line pins both. The second test of the area passes
unchanged.

## Notes for the loop
- Touches `src/{d['area']}/` only. Independent of in-flight work.
- Not a critical path.
"""


# --- the scenario files ----------------------------------------------------

def heredoc(path, text, tag):
    if not text.endswith("\n"):
        text += "\n"
    return "cat > %s <<'%s'\n%s%s\n" % (path, tag, text, tag)


def seed_sh(seed, lang, d, place, fmt):
    n = names(lang, d)
    js = lang == "javascript"
    ext = ".js" if js else ".py"
    out = [
        "# Generated by evals/lab/generators/transparent.py, seed %d." % seed,
        "# language=%s domain=%s place=%s format=%s" % (lang, d["key"], place, fmt),
        "#",
        "# The transparent outcome. One value of the code is repeated in prose, and",
        "# the Plan changes that value and says nothing about the docs. The repeat",
        "# hides in the `%s` place, and it states the value in the `%s` format." % (place, fmt),
        "# Two distractors pull the other way: the `## Behaviour` list of the",
        "# governed Note contradicts the code, and a second Decision states a value",
        "# for %s that the code no longer has. Both were false before the Plan." % d["const2"],
        "",
    ]
    if js:
        out.append("mkdir -p src/%s src/%s docs/notes docs/decisions .plans/%s"
                   % (d["area"], d["neighbour"], d["area"]))
        files = {
            "src/%s/%s" % (d["area"], n["module"]): area_source(lang, d, n),
            "src/%s/%s.test.js" % (d["area"], d["module"]): area_test(lang, d, n),
            "src/%s/%s" % (d["neighbour"], n["nmodule"]): neighbour_source(lang, d, n, comment_lines(lang, d, place, fmt)),
            "src/%s/%s.test.js" % (d["neighbour"], d["neighbour_module"]): neighbour_test(lang, d, n),
        }
    else:
        out += [
            "# A Python fixture, as python-structure builds one: the base seed installed",
            "# the Node adapter, so this seed removes every Node trace and runs hone's",
            "# own setup.sh again.",
            "command -v uv >/dev/null && command -v uvx >/dev/null \\",
            "    || { echo \"this fixture needs uv and uvx on PATH\" >&2; exit 1; }",
            "rm -f package.json scripts/run-tests.sh",
            "cat > pyproject.toml <<'PYPROJECT'",
            "[project]",
            'name = "lab-fixture"',
            'version = "0.0.0"',
            'requires-python = ">=3.11"',
            "dependencies = []",
            "",
            "[dependency-groups]",
            'dev = ["pytest>=8"]',
            "",
            "[tool.pytest.ini_options]",
            'pythonpath = ["src"]',
            'testpaths = ["tests"]',
            "PYPROJECT",
            'CLAUDE_PROJECT_DIR="$PWD" bash "$LAB_PLUGIN/scripts/setup.sh" >/dev/null 2>&1 \\',
            '    || { echo "hone\'s setup.sh failed on the generated Python fixture" >&2; exit 1; }',
            "grep -q 'uv run pytest' scripts/run-tests.sh \\",
            '    || { echo "setup.sh installed no Python test adapter" >&2; exit 1; }',
            "for entry in '.venv/' '__pycache__/' '.pytest_cache/'; do",
            '    grep -qxF "$entry" .gitignore || printf \'%s\\n\' "$entry" >> .gitignore',
            "done",
            "mkdir -p src/%s src/%s tests docs/notes docs/decisions .plans/%s"
            % (d["area"], d["neighbour"], d["area"]),
        ]
        files = {
            "src/%s/__init__.py" % d["area"]: '"""%s"""\n' % d["area"].capitalize(),
            "src/%s/__init__.py" % d["neighbour"]: '"""%s"""\n' % d["neighbour"].capitalize(),
            "src/%s/%s" % (d["area"], n["module"]): area_source(lang, d, n),
            "src/%s/%s" % (d["neighbour"], n["nmodule"]): neighbour_source(lang, d, n, comment_lines(lang, d, place, fmt)),
            "tests/test_%s.py" % d["module"]: area_test(lang, d, n),
            "tests/test_%s.py" % d["neighbour_module"]: neighbour_test(lang, d, n),
        }
    files.update(docs(d, n, place, fmt))
    files[".plans/%s.md" % d["slug"]] = plan(lang, d, n)
    for i, (path, text) in enumerate(files.items()):
        out.append(heredoc(path, text, "HONE_GEN_%d" % i))
    if not js:
        # Resolve the test dependency once, so that uv.lock is part of the seed
        # commit. Without it the first call of the adapter writes uv.lock into
        # the primary tree, and `revertible` reads that as a dirty tree.
        out += [
            "uv sync --quiet >/dev/null 2>&1 \\",
            '    || { echo "uv sync could not build the fixture environment" >&2; exit 1; }',
        ]
    out += [
        "bash scripts/run-tests.sh --all >/dev/null 2>&1 \\",
        '    || { echo "the seeded suite is red, so no run of this scenario would mean anything" >&2; exit 1; }',
    ]
    return "\n".join(out) + "\n"


def comment_lines(lang, d, place, fmt):
    """The header comment of the neighbour module. A python module says its map
    in the docstring already, so only the hidden sentence goes into a comment
    there."""
    lines = []
    if lang == "javascript":
        lines.append(d["nmap"].format(nmodule="This module", area=d["area"]).replace("`", ""))
    if place == "comment":
        lines.append(hidden_sentence(d, place, fmt))
    return lines


def hidden_path(d, n, place):
    if place == "own":
        return "docs/notes/%s.md" % d["area"]
    if place == "neighbour":
        return "docs/notes/%s.md" % d["neighbour"]
    if place == "untied":
        return "docs/decisions/%s-rule.md" % d["area"]
    if place == "readme":
        return "src/%s/README.md" % d["neighbour"]
    return "src/%s/%s" % (d["neighbour"], n["nmodule"])


PAST = (r"\b(old|former|formerly|previous|previously|earlier|was|were|used to|until|before|"
        r"up from|down from|no longer|last|since|raised|lowered|rose|left|lost|losing|"
        r"measured|found|agreed|took effect)\b")


def check_sh(lang, d, place, fmt):
    n = names(lang, d)
    (lo, rlo), (hi, rhi) = boundary(d["op"], d["new"])
    if lang == "javascript":
        proof = ("[ \"$(node -e 'const { %s: f } = require(\"./src/%s/%s\"); console.log(f(%d), f(%d))' 2>/dev/null)\" = \"%s %s\" ]"
                 % (n["fn"], d["area"], n["module"], lo, hi, lit(lang, rlo), lit(lang, rhi)))
    else:
        proof = ("[ \"$(PYTHONPATH=src python3 -c 'from %s.%s import %s as f; print(f(%d), f(%d))' 2>/dev/null)\" = \"%s %s\" ]"
                 % (d["area"], d["module"], n["fn"], lo, hi, lit(lang, rlo), lit(lang, rhi)))
    hidden = hidden_path(d, n, place)
    if place == "comment":
        extract = "grep -E '^[[:space:]]*(//|#)' %s 2>/dev/null" % hidden
    else:
        extract = "cat %s 2>/dev/null" % hidden
    return f"""# Generated by evals/lab/generators/transparent.py.
# language={lang} domain={d['key']} place={place} format={fmt}
#
# The outcome: after the run, no document states the old value of the changed
# rule as today's rule. The hidden repeat sits in {hidden}, and it
# states the value in the `{fmt}` format. The old value reads as
# "{rendering(d, fmt, 'old')}", and the new one as
# "{rendering(d, fmt, 'new')}".
#
# The state of the hidden text, one sentence at a time. A sentence about the
# past is true, so it counts as `history` and not as `stale`.
#   cut      no value of the rule is left there
#   updated  it states the new value as today's rule: true, and still a copy
#   history  it names a value only inside a clause about the past
#   stale    it states the old value as today's rule, so it is now false
#   gone     the run deleted the text
landed {d['slug']}
suite_green
plan_deleted {d['slug']}
worktree_removed
revertible
commits_conform
review_ran
{proof} \\
    && ok "the Plan's own proof holds on main" || bad "the Plan's own proof does not hold on main"

OLD='{patterns(d, fmt)[0]}'
NEW='{patterns(d, fmt)[1]}'
PAST='{PAST}'
sentences() {{ tr '\\n' ' ' | sed 's/\\([.:]\\) /\\1\\n/g'; }}
state_of() {{
    local text="$1" asserted
    [ -n "$text" ] || {{ echo gone; return; }}
    asserted=$(printf '%s\\n' "$text" | sentences | grep -viE "$PAST")
    if grep -qE "$NEW" <<<"$asserted"; then echo updated
    elif grep -qE "$OLD" <<<"$asserted"; then echo stale
    elif grep -qE "$NEW|$OLD" <<<"$text"; then echo history
    else echo cut
    fi
}}
hidden=$(state_of "$({extract})")
measure hidden "$hidden"
true_docs=yes
[ "$hidden" = stale ] && true_docs=no
goal docs_true "$true_docs" yes

# The governed Note carries a list that repeats the code. A Note is a map and
# one invariant, so consolidate should cut the list.
note=cut
grep -qE '^- ' docs/notes/{d['area']}.md 2>/dev/null && note=kept
measure note_spec "$note"

# The two distractors. Both were false before the Plan, so neither decides the
# verdict. `kept` means the run left the false sentence standing.
contra=fixed
grep -qE '{d['pat_contra']}' docs/notes/{d['area']}.md 2>/dev/null && contra=kept
measure contra "$contra"
stale_decision=fixed
grep -qE '{d['pat_stale']}' docs/decisions/{d['area']}-parts.md 2>/dev/null && stale_decision=kept
measure stale_decision "$stale_decision"

# No run may answer a false sentence by deleting what the document is for.
grep -qE '^Invariant: ' docs/notes/{d['area']}.md 2>/dev/null \\
    && ok "the {d['area']} Note keeps its invariant" || bad "the run deleted the invariant of the {d['area']} Note"
grep -qE '^Invariant: ' docs/notes/{d['neighbour']}.md 2>/dev/null \\
    && ok "the {d['neighbour']} Note keeps its invariant" || bad "the run deleted the invariant of the {d['neighbour']} Note"
[ -s docs/decisions/{d['area']}-rule.md ] \\
    && ok "the Decision on the rule is still there" || bad "the run deleted the Decision on the rule"
"""


def write_scenario(seed, out_root):
    lang, d, place, fmt = params_for(seed)
    name = scenario_name(seed)
    path = pathlib.Path(out_root) / name
    path.mkdir(parents=True, exist_ok=True)
    (path / "track").write_text("behavioral\n")
    (path / "prompt").write_text("/hone:run %s\n" % d["slug"])
    (path / "seed.sh").write_text(seed_sh(seed, lang, d, place, fmt))
    (path / "check.sh").write_text(check_sh(lang, d, place, fmt))
    (path / "goals").write_text("docs_true yes\n")
    (path / "params.json").write_text(json.dumps(
        dict(seed=seed, name=name, language=lang, domain=d["key"], place=place,
             format=fmt, change=d["slug"],
             old=rendering(d, fmt, "old"),
             new=rendering(d, fmt, "new"),
             hidden_in=hidden_path(d, names(lang, d), place)), indent=2) + "\n")
    return path


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("seeds", nargs="*", type=int, help="the seed numbers to write")
    ap.add_argument("--range", nargs=2, type=int, metavar=("FIRST", "LAST"),
                    help="every seed from FIRST to LAST")
    ap.add_argument("--out", default="/var/tmp/hone-lab-generated",
                    help="the directory that run.sh reads as $LAB_SCENARIOS")
    ap.add_argument("--list", action="store_true",
                    help="print the parameters of each seed and write nothing")
    a = ap.parse_args(argv)
    seeds = list(a.seeds)
    if a.range:
        seeds += list(range(a.range[0], a.range[1] + 1))
    if not seeds:
        ap.error("give at least one seed, or --range")
    for s in seeds:
        if s < 0:
            ap.error("a seed is not negative")
        lang, d, place, fmt = params_for(s)
        if a.list:
            print("%-4d %-28s %-10s %-10s %-10s %s"
                  % (s, scenario_name(s), lang, d["key"], place, fmt))
        else:
            print(write_scenario(s, a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
