#!/bin/bash
# Judge one candidate change to hone: accept, reject, or undecided. The
# candidate is the working tree against a base ref. docs/development.md has
# the method and the reason for every rule. This script is that method as
# code, and it makes no model call. The runs that it reads are yours to make, with
# evals/run.sh --json and evals/lab/run.sh, once per arm:
#   the baseline arm   the plugin at the base ref
#   the candidate arm  the plugin with the candidate applied
#
# Usage:
#   bash evals/candidate.sh plan   [--ref REF] [--state-change]
#   bash evals/candidate.sh decide [--ref REF] [--state-change]
#                                  [--base DIR[,DIR]] [--cand DIR[,DIR]]
#                                  [--unit-base FILE[,FILE]] [--unit-cand FILE[,FILE]]
#   plan     reads the diff alone. It prints the suites that the candidate
#            owes, what they cost, the upgrade path it carries, and how much
#            it grows or shrinks the shipped plugin.
#   decide   reads the diff and the results of both arms, and it prints one
#            line per finding and then the verdict.
#   --ref REF        the base of the candidate (default HEAD)
#   --state-change   the candidate alters what hone leaves in a consumer
#                    repository. The script sees that by itself only for
#                    templates/ and scripts/setup.sh. Pass the flag for the
#                    rest, such as a new shape of a document under docs/.
#   --base, --cand   run directories of evals/lab/run.sh, one per pass
#   --unit-base, --unit-cand   files that evals/run.sh --json wrote
#
# The lines of decide:
#   REJECT     a constraint broke, or an outcome dropped
#   UNDECIDED  the evidence is too thin, and the line names the run to make
#   GAIN       a measured outcome moved up by more than the noise
#   NOTE       a tally inside the noise, the distinct endings per scenario,
#              how many runs reached for what a guard forbids, and a scenario
#              whose two arms are one plugin, which drops out of the comparison
#   PRICE      the dollars and minutes of each arm, and the size of the plugin
#
# Two runs are one plugin for a scenario when they agree on every shipped path
# that the scenario loads (plugin_files in result.json, and owed() read
# backwards). So a baseline that differs only in a path the scenario never
# loads still counts. A run from before that field compares as a whole plugin.
#
# The verdict: reject on any REJECT. Undecided on any UNDECIDED. A candidate
# that grows the shipped prose is accepted only with a GAIN. A deterministic
# check may grow the shipped code on the constraints alone. Every other
# candidate is accepted.
#
# Exit: 0 accept (or plan), 1 reject, 3 undecided, 2 usage.
set -uo pipefail

EVALS=$(cd "$(dirname "$0")" && pwd)
ROOT="${CANDIDATE_ROOT:-$(cd "$EVALS/.." && pwd)}"
SCENARIOS="${LAB_SCENARIOS:-$ROOT/evals/lab/scenarios}"
FLOORS="$ROOT/evals/floors"
SHIPPED=(agents hooks rules scripts skills templates)

# What one evaluation costs, in dollars at API prices. Measured 2026-09-18 on
# claude-opus-5: a full unit pass at three votes over 24 cases cost 3.80, and
# a full lab pass over sixteen scenarios cost 36 and took 65 minutes.
USD_PER_CASE_3_VOTES=0.16
USD_PER_LAB_RUN=2.3
# A measure is a count over few runs. It needs this many runs per arm, and a
# move of fewer than MOVE runs is noise.
RUNS_PER_ARM=3
MOVE=2
# A tally that moved is decided at this many votes per arm.
VOTES_TO_DECIDE=10

MODE="${1:-}"; [ $# -gt 0 ] && shift
REF=HEAD; STATE_CHANGE=0; BASE_DIRS=""; CAND_DIRS=""; UNIT_BASE=""; UNIT_CAND=""
while [ $# -gt 0 ]; do
    case "$1" in
        --ref) shift; REF="$1" ;;
        --state-change) STATE_CHANGE=1 ;;
        --base) shift; BASE_DIRS="$1" ;;
        --cand) shift; CAND_DIRS="$1" ;;
        --unit-base) shift; UNIT_BASE="$1" ;;
        --unit-cand) shift; UNIT_CAND="$1" ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$MODE" in plan|decide) ;; *) echo "usage: candidate.sh plan|decide [...] (see the header)" >&2; exit 2 ;; esac
command -v jq >/dev/null || { echo "candidate.sh needs jq" >&2; exit 2; }
git -C "$ROOT" rev-parse --verify -q "$REF^{commit}" >/dev/null || { echo "--ref: no such commit: $REF" >&2; exit 2; }

# ---------------------------------------------------------------- the diff

CHANGED=$( { git -C "$ROOT" diff --name-only "$REF" --; git -C "$ROOT" ls-files --others --exclude-standard; } | sort -u)
# The paths that owed() reads. It is the candidate's diff, and owed_for sets it
# to one shipped path, to ask which suites that path alone owes.
PATHS=$CHANGED
touches() { printf '%s\n' "$PATHS" | grep -E "$1" >/dev/null; }

# The suites that the candidate owes, one word per line: `mechanical`,
# `unit:<target>`, `lab:<scenario>`, `lab:all`. This is the table of
# .claude/rules/releasing.md, plus the two seeded scenarios for the critic
# that consolidate calls, because its unit target pins three paragraphs of it.
owed() {
    touches '^(hooks|scripts|templates)/|^evals/(run\.sh|candidate\.sh|lab/)|^test/' && echo mechanical
    touches '^agents/plan-critic\.md$' && echo unit:plan-critic
    if touches '^agents/consolidate-critic\.md$'; then
        echo unit:consolidate-critic; echo lab:seeded-prose; echo lab:seeded-structure
    fi
    # The two skills that a person calls. The plan skill has two scenarios:
    # a sketch it must carry through, and a sketch it must hand back.
    if touches '^skills/plan/|^agents/plan-critic\.md$'; then
        echo lab:plan-clear; echo lab:plan-fork
    fi
    touches '^skills/setup/|^scripts/setup\.sh$|^templates/' && echo lab:setup-misfit
    # The one file of another skill that the plan skill reads. Its reference
    # in skills/plan/SKILL.md is the only one across skill directories, and
    # loads() reads this line backwards to compare the plan scenarios on it.
    if touches '^skills/run/references/dependency-refresh\.md$'; then echo lab:plan-clear; echo lab:plan-fork; fi
    touches '^skills/run/' && echo unit:loop
    touches '^skills/garden/' && echo unit:garden
    if touches '^rules/workflow\.md$'; then
        local t; for t in plan-critic consolidate-critic loop garden; do echo "unit:$t"; done
    fi
    touches '^(hooks|scripts)/|^skills/run/|^rules/workflow\.md$' && echo lab:all
    return 0
}
OWED=$(owed | sort -u)
# The suites that one path owes, from the same table.
owed_for() { local PATHS="$1"; owed | sort -u; }

# Does the scenario $1 load the shipped path $2? This is owed() read backwards:
# a path owes the suites that a change to it must run, so a scenario loads a
# path when that path owes it. Only a skill directory narrows the answer,
# because a session calls one skill: `lab:all` from skills/run/ leaves out the
# scenarios that another skill directory claims. Everywhere else the table is
# coarser than the truth (every loop session reads the consolidate critic, and
# every fixture is seeded from templates/), so those paths count in every
# scenario, which is the strict answer. A path that owes nothing at all counts
# too, except under .claude-plugin/: a version string loads in no scenario.
loads() {
    local suites; suites=$(owed_for "$2")
    [ -n "$suites" ] || { case "$2" in .claude-plugin/*) return 1 ;; *) return 0 ;; esac; }
    printf '%s\n' "$suites" | grep -qx "lab:$1" && return 0
    if printf '%s\n' "$suites" | grep -qx 'lab:all'; then
        case "$2" in skills/*) claimed_elsewhere "$1" "$2" && return 1 ;; esac
        return 0
    fi
    case "$2" in skills/*) return 1 ;; esac
    return 0
}
# Does a skill directory other than the one of path $2 claim scenario $1?
claimed_elsewhere() {
    local d x="${2#skills/}"; x=${x%%/*}
    for d in "$ROOT"/skills/*/; do
        d=$(basename "$d"); [ "$d" = "$x" ] && continue
        owed_for "skills/$d/SKILL.md" | grep -qx "lab:$1" && return 0
    done
    return 1
}

# A shipped path that owed() does not know has no suite, so a change to it is
# outside what the method can judge (rule 1 of docs/development.md: coverage
# sets the limit). A new skill or a new rule file lands here.
UNMEASURED=$(printf '%s\n' "$CHANGED" | grep -E "^($(IFS='|'; echo "${SHIPPED[*]}"))/" \
    | grep -vE '^(agents|hooks|scripts|templates)/|^skills/(run|garden|plan|setup)/|^rules/workflow\.md$' || true)

# The upgrade path: none needed, mechanical, manual, or missing.
upgrade_path() {
    local state=$STATE_CHANGE
    touches '^templates/|^scripts/setup\.sh$' && state=1
    if [ "$state" -eq 0 ]; then echo none-needed
    elif touches '^scripts/setup\.sh$|^skills/garden/'; then
        touches '^docs/upgrading\.md$' && echo mechanical-and-manual || echo mechanical
    elif touches '^docs/upgrading\.md$'; then echo manual
    else echo missing
    fi
}

# The size of the shipped plugin in words, at the base ref ($1) or in the
# tree, for one kind ($2). `prose` is what a model reads and executes: the .md
# and .txt files. `code` is the rest, which is the hooks and the scripts. The
# two count apart, because only prose must show a gain when it grows. A
# deterministic check is preferred wherever a question is computable
# (docs/model.md, Checking), so it enters on the constraints alone.
size_words() {
    local d total=0 tmp
    tmp=$(mktemp -d)
    for d in "${SHIPPED[@]}"; do
        if [ "$1" = tree ]; then
            # Tracked files and new files that git does not ignore: what a
            # commit of the candidate would hold. An ignored scratch file in a
            # shipped directory must not read as growth.
            [ -d "$ROOT/$d" ] && (cd "$ROOT" && { git ls-files -z -- "$d"; git ls-files -z --others --exclude-standard -- "$d"; } \
                | while IFS= read -r -d '' f; do [ -f "$f" ] && mkdir -p "$tmp/$(dirname "$f")" && cp "$f" "$tmp/$f"; done)
        else
            git -C "$ROOT" archive "$1" -- "$d" 2>/dev/null | tar -x -C "$tmp" 2>/dev/null
        fi
    done
    if [ "$2" = prose ]; then
        total=$(find "$tmp" -type f \( -name '*.md' -o -name '*.txt' \) -exec cat {} + | wc -w)
    else
        total=$(find "$tmp" -type f ! -name '*.md' ! -name '*.txt' -exec cat {} + | wc -w)
    fi
    rm -rf "$tmp"
    echo "$total"
}

scenario_count() { find "$SCENARIOS" -mindepth 2 -maxdepth 2 -name check.sh | wc -l; }
case_count() { find "$ROOT/evals/$1" -mindepth 2 -maxdepth 2 -name expected 2>/dev/null | wc -l; }

print_plan() {
    local o t n usd=0 line
    echo "candidate: $(printf '%s\n' "$CHANGED" | grep -c .) changed file(s) against $REF"
    [ -n "$OWED" ] || echo "  owes no suite"
    for o in $OWED; do
        case "$o" in
            mechanical) echo "  owes  bash test/run.sh                                  no model call" ;;
            unit:*)
                t=${o#unit:}; n=$(case_count "$t")
                line=$(jq -n --argjson n "$n" --argjson c "$USD_PER_CASE_3_VOTES" '$n * $c * 2 | . * 100 | round / 100')
                usd=$(jq -n --argjson a "$usd" --argjson b "$line" '$a + $b')
                echo "  owes  evals/run.sh $t --votes 3 --json F             both arms, about $line dollars" ;;
            lab:all)
                n=$(scenario_count)
                line=$(jq -n --argjson n "$n" --argjson c "$USD_PER_LAB_RUN" '$n * $c | round')
                usd=$(jq -n --argjson a "$usd" --argjson b "$line" '$a + $b')
                echo "  owes  evals/lab/run.sh                                  the candidate arm, about $line dollars and one hour" ;;
            lab:*)
                line=$(jq -n --argjson r "$RUNS_PER_ARM" --argjson c "$USD_PER_LAB_RUN" '$r * $c * 2 | round')
                usd=$(jq -n --argjson a "$usd" --argjson b "$line" '$a + $b')
                echo "  owes  evals/lab/run.sh ${o#lab:}, $RUNS_PER_ARM runs per arm   about $line dollars" ;;
        esac
    done
    if printf '%s\n' "$OWED" | grep -x 'lab:all' >/dev/null; then
        line=$(jq -n --argjson r "$RUNS_PER_ARM" --argjson c "$USD_PER_LAB_RUN" --argjson g "$(loop_goal_scenarios | grep -c .)" '$g * ($r * 2 - 1) * $c | round')
        usd=$(jq -n --argjson a "$usd" --argjson b "$line" '$a + $b')
        echo "  owes  each /hone:run scenario with a goals file, $RUNS_PER_ARM runs per arm   about $line dollars more"
    fi
    echo "  a baseline arm that an earlier candidate measured on the same base counts again"
    echo "  total: about $usd dollars at API prices"
    [ -z "$UNMEASURED" ] || echo "  no suite measures: $(printf '%s' "$UNMEASURED" | tr '\n' ' ')"
    echo "  upgrade path: $(upgrade_path)"
    echo "  size: prose $(size_words "$REF" prose) words at $REF and $(size_words tree prose) in the tree, code $(size_words "$REF" code) and $(size_words tree code)"
}

goal_scenarios() { local f; for f in "$SCENARIOS"/*/goals; do [ -f "$f" ] && basename "$(dirname "$f")"; done; return 0; }
# The goal scenarios of the loop: what a candidate that owes the whole lab
# also owes at three runs per arm. A scenario whose prompt calls another skill
# measures that skill, and only a change to that skill owes it three times.
loop_goal_scenarios() {
    local s
    for s in $(goal_scenarios); do
        case "$(head -c 12 "$SCENARIOS/$s/prompt" 2>/dev/null)" in /hone:run*|"") echo "$s" ;; /hone:*) ;; *) echo "$s" ;; esac
    done
    return 0
}

if [ "$MODE" = plan ]; then print_plan; exit 0; fi

# ------------------------------------------------------------- the results

FINDINGS=$(mktemp); trap 'rm -f "$FINDINGS"' EXIT
say() { printf '%s\n' "$*" >> "$FINDINGS"; }

# Every result.json of the lab run directories of one arm, as JSON lines.
lab_records() {
    local arm="$1" dirs="$2" d r
    IFS=, read -ra list <<<"$dirs"
    for d in "${list[@]}"; do
        [ -d "$d" ] || { echo "no such run directory: $d" >&2; exit 2; }
        ls "$d"/*/result.json >/dev/null 2>&1 \
            || { echo "no result.json below $d. Pass the directory of one lab pass, /var/tmp/hone-lab/<time>, after the pass ended." >&2; exit 2; }
        for r in "$d"/*/result.json; do
            jq -c --arg arm "$arm" '. + {arm: $arm}' "$r" || { echo "cannot read $r" >&2; exit 2; }
        done
    done
}
unit_records() {
    local arm="$1" files="$2" f
    IFS=, read -ra list <<<"$files"
    for f in "${list[@]}"; do
        [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }
        jq -c --arg arm "$arm" '. + {arm: $arm}' "$f" || { echo "cannot read $f as the JSON lines of evals/run.sh --json" >&2; exit 2; }
    done
}
LAB=$( { [ -z "$BASE_DIRS" ] || lab_records base "$BASE_DIRS"; [ -z "$CAND_DIRS" ] || lab_records cand "$CAND_DIRS"; } ) || exit 2
UNIT=$( { [ -z "$UNIT_BASE" ] || unit_records base "$UNIT_BASE"; [ -z "$UNIT_CAND" ] || unit_records cand "$UNIT_CAND"; } ) || exit 2

# The goals of every scenario, as {scenario: {measure: value}}. A stop must
# hand the person one action, in every scenario.
GOALS=$(for s in $(goal_scenarios); do
            jq -Rn --arg s "$s" '{($s): ([inputs | select(test("^[^# ]+ +[^ ]+$")) | split(" ") | {(.[0]): .[-1]}] | add // {})}' "$SCENARIOS/$s/goals"
        done | jq -s 'add // {}')
# {suite: [model, ...]}. A unit target has one model. The lab has its floor
# first, and then the models below it on which a guard may be measured.
FLOOR_MAP=$(grep -vE '^[[:space:]]*(#|$)' "$FLOORS" 2>/dev/null | jq -Rn '[inputs | split(" ") | {(.[0]): .[1:]}] | add // {}')

# The constraints first: a suite that the candidate owes and did not run.
for o in $OWED; do
    case "$o" in
        mechanical)
            if bash "$ROOT/test/run.sh" >/dev/null 2>&1; then say "NOTE mechanical: test/run.sh is green"
            else say "REJECT mechanical: test/run.sh is red"; fi ;;
        unit:*)
            jq -es --arg t "${o#unit:}" 'map(select(.arm == "cand" and .target == $t)) | length > 0' <<<"$UNIT" >/dev/null \
                || say "UNDECIDED unit ${o#unit:}: the candidate owes this target, and --unit-cand has no record of it" ;;
        lab:all)
            for s in "$SCENARIOS"/*/; do
                [ -f "$s/check.sh" ] || continue
                jq -es --arg s "$(basename "$s")" 'map(select(.arm == "cand" and .scenario == $s)) | length > 0' <<<"$LAB" >/dev/null \
                    || say "UNDECIDED lab $(basename "$s"): the candidate owes the whole lab, and --cand has no run of this scenario"
            done ;;
        lab:*)
            jq -es --arg s "${o#lab:}" 'map(select(.arm == "cand" and .scenario == $s)) | length > 0' <<<"$LAB" >/dev/null \
                || say "UNDECIDED lab ${o#lab:}: the candidate owes this scenario, and --cand has no run of it" ;;
    esac
done
[ -z "$UNMEASURED" ] || say "UNDECIDED coverage: no suite measures $(printf '%s' "$UNMEASURED" | tr '\n' ' '). Grow a measurement first."
case "$(upgrade_path)" in
    missing) say "REJECT upgrade: the candidate alters what hone leaves in a consumer repository, and it carries no path in scripts/setup.sh, in /hone:garden, or in docs/upgrading.md" ;;
    manual) say "PRICE upgrade: a person must act in every consumer repository (docs/upgrading.md). A mechanical path would be cheaper." ;;
esac

# The scenarios whose measures the candidate owes at RUNS_PER_ARM runs.
THRICE=$( { printf '%s\n' "$OWED" | sed -n 's/^lab://p' | grep -vx all
            printf '%s\n' "$OWED" | grep -qx 'lab:all' && loop_goal_scenarios; } | sort -u | jq -R . | jq -s .)

# The shipped paths where the runs of one scenario disagree, one `scenario
# <tab> path` per line, and then the same list narrowed to the paths that the
# scenario loads. Two runs are one plugin for a scenario when they agree on
# those paths alone. A run from before plugin_files has no paths, and every
# run of its scenario falls back to the hash of the whole plugin.
DIFFS=$(jq -rs '
    group_by(.scenario)[] | select(length > 1 and all(.plugin_files != null)) | . as $rs
    | ($rs | map(.plugin_files | keys_unsorted) | add | unique)[] as $p
    | select(($rs | map(.plugin_files[$p] // "") | unique | length) > 1)
    | "\($rs[0].scenario)\t\($p)"' <<<"$LAB")
LOADS=$(while IFS=$'\t' read -r s p; do
            if [ -n "$p" ] && loads "$s" "$p"; then printf '%s\t%s\n' "$s" "$p"; fi
        done <<<"$DIFFS" \
        | jq -Rn '[inputs | split("\t")] | group_by(.[0]) | map({key: .[0][0], value: map(.[1])}) | from_entries')

# The lab: verdicts, goals, endings, price.
jq -rs --argjson goals "$GOALS" --argjson thrice "$THRICE" --argjson floors "$FLOOR_MAP" --argjson need "$RUNS_PER_ARM" --argjson move "$MOVE" \
   --argjson loads "$LOADS" '
    def arm(a): map(select(.arm == a));
    def held(m; g): map(select(.measures[m]? != null)) | {n: length, held: (map(select(.measures[m] == g)) | length)};
    def mean(f): if length == 0 then 0 else (map(f) | add / length) end;
    def runs: . * 1000 | round / 1000;
    # What each run measured, for its own scenario: the hashes of the paths
    # that the scenario loads, or the whole plugin when a run predates them.
    (group_by(.scenario) | map(. as $rs | ($rs | all(.plugin_files != null)) as $fine | $rs[0].scenario as $s
        | map(. + {ident: (if $fine then ([($loads[$s] // [])[] as $p | .plugin_files[$p] // ""] | join("|"))
                           else .plugin // "" end)})) | add // [])
    | (group_by(.scenario)[] | . as $rs | $rs[0].scenario as $s
       | ($rs | arm("base") | map(.ident) | unique) as $bi | ($rs | arm("cand") | map(.ident) | unique) as $ci
       | (if ($bi | length) > 1 then "UNDECIDED lab \($s): the baseline runs measured \($bi | length) different plugins" else empty end),
         (if ($ci | length) > 1 then "UNDECIDED lab \($s): the candidate runs measured \($ci | length) different plugins" else empty end),
         (if ($bi | length) == 1 and $bi == $ci
          then "NOTE lab \($s): both arms measured the same plugin here, so these runs say nothing about the candidate"
          else empty end)),
      (group_by(.scenario) | map(select((arm("base") | length) > 0 and (arm("cand") | length) > 0)) as $both
       | if ($both | length) > 0 and ($both | all((arm("base") | map(.ident) | unique) == (arm("cand") | map(.ident) | unique)))
         then "UNDECIDED lab: no scenario told the two arms apart, so no run measured the candidate" else empty end),
      (map(select(.model as $m | ($floors.lab // [$m]) | index($m) | not)) | map(.model) | unique
       | map("UNDECIDED lab: a run used \(.), and evals/floors allows \($floors.lab | join(", ")) for the lab") | .[]),
      (group_by(.scenario)[] | select((arm("cand") | length) > 0 and (arm("base") | length) > 0)
       | select((arm("base") | map(.model) | unique) != (arm("cand") | map(.model) | unique))
       | "UNDECIDED lab \(.[0].scenario): the two arms ran on different models"),
      (group_by(.scenario)[] | . as $rs | $rs[0].scenario as $s | ($rs | arm("base")) as $b | ($rs | arm("cand")) as $c
       | select(($c | length) > 0)
       # A scenario whose two arms are one plugin drops out: its runs compare
       # the baseline with itself, and the line above says so.
       | select(($b | length) == 0 or ($b | map(.ident) | unique) != ($c | map(.ident) | unique))
       | ($c | map(select(.verdict == "fail")) | length) as $cf | ($b | map(select(.verdict == "fail")) | length) as $bf
       | ($c | map(select(.verdict == "indeterminate")) | length) as $ci
       | ($b | map(select(.verdict != "indeterminate"))) as $bok | ($c | map(select(.verdict != "indeterminate"))) as $cok
       | (if $ci > 0 then "UNDECIDED lab \($s): \($ci) candidate run(s) were indeterminate. Run them again." else empty end),
         (if $cf > 0 and (($b | length) == 0 or ($cf / ($c | length)) > ($bf / ($b | length)))
          then "REJECT lab \($s): \($cf) of \($c | length) candidate run(s) failed (baseline \($bf) of \($b | length)): \($c | map(select(.verdict == "fail")) | .[0].reason)"
          elif $bf > 0 and $cf == 0 and ($b | length) >= $need and ($c | length) >= $need and $bf >= $move
          then "GAIN lab \($s): the baseline failed \($bf) of \($b | length) runs, and the candidate failed none of \($c | length)"
          else empty end),
         ((($goals[$s] // {}) + {stop_actionable: "yes"}) | to_entries[] | .key as $m | .value as $g
          | ($bok | held($m; $g)) as $bh | ($cok | held($m; $g)) as $ch
          | select($ch.n > 0 or ($goals[$s][$m]? != null))
          | if $bh.n < $need or $ch.n < $need then
                (if $goals[$s][$m]? != null and ($thrice | index($s)) != null
                 then "UNDECIDED lab \($s): the measure \($m) has \($bh.n) baseline and \($ch.n) candidate run(s), and it needs \($need) per arm"
                 else empty end)
            else (($ch.held / $ch.n - $bh.held / $bh.n) * ([$bh.n, $ch.n] | min) | runs) as $d
              | if $d <= -$move then "REJECT lab \($s): the outcome \($m)=\($g) dropped from \($bh.held)/\($bh.n) runs to \($ch.held)/\($ch.n)"
                elif $d >= $move then "GAIN lab \($s): the outcome \($m)=\($g) rose from \($bh.held)/\($bh.n) runs to \($ch.held)/\($ch.n)"
                else "NOTE lab \($s): \($m)=\($g) in \($bh.held)/\($bh.n) baseline and \($ch.held)/\($ch.n) candidate runs" end
            end),
         (($bok | map(.ending) | unique | length) as $be | ($cok | map(.ending) | unique | length) as $ce
          | if ($bok | length) >= $need and ($cok | length) >= $need and ($ce - $be) >= $move
            then "REJECT lab \($s): the runs ended \($ce) ways, and the baseline ended \($be) way(s), so the candidate is less predictable"
            elif ($cok | length) > 1 then "NOTE lab \($s): \($ce) distinct ending(s) in \($cok | length) candidate runs, \($be) in \($bok | length) baseline runs"
            else empty end),
         # A verdict cannot tell a guard that turned a run back from a run
         # that never reached. The count says which one the verdicts show.
         (($bok + $cok) | map(select(.measures.reached? != null)) | select(length > 0)
          | (($bok | held("reached"; "yes")) as $br | ($cok | held("reached"; "yes")) as $cr
             | "NOTE lab \($s): the run reached for the primary tree in \($br.held)/\($br.n) baseline and \($cr.held)/\($cr.n) candidate runs"
               + (if $br.held + $cr.held == 0 then ". No run reached, so these verdicts say nothing about a guard." else "" end)))),
      ([group_by(.scenario)[] | select((arm("base") | length) > 0 and (arm("cand") | length) > 0)
        | {b: (arm("base") | mean(.cost_usd + .nested_cost_usd)), c: (arm("cand") | mean(.cost_usd + .nested_cost_usd)),
           bm: (arm("base") | mean(.seconds / 60)), cm: (arm("cand") | mean(.seconds / 60))}]
       | select(length > 0)
       | "PRICE lab: over \(length) scenario(s) in both arms, a run costs \(map(.b) | add | . * 100 | round / 100) dollars and \(map(.bm) | add | round) minutes at the baseline, and \(map(.c) | add | . * 100 | round / 100) dollars and \(map(.cm) | add | round) minutes with the candidate")
' <<<"$LAB" >> "$FINDINGS"

# The unit evals: a flipped plurality rejects. A tally that moved without a
# flip is decided at VOTES_TO_DECIDE votes per arm, because one vote in three
# dissents on an unchanged prompt a few times per pass.
jq -rs --argjson floors "$FLOOR_MAP" --argjson votes "$VOTES_TO_DECIDE" --argjson move "$MOVE" '
    def arm(a): map(select(.arm == a));
    def right: map(select(.token == .expected)) | length;
    def runs: . * 1000 | round / 1000;
    (map(select(.model != ($floors[.target][0] // .model))) | map("\(.target) on \(.model), and its floor is \($floors[.target][0])") | unique
     | map("UNDECIDED unit: a run measured \(.)") | .[]),
    (group_by([.target, .case])[] | . as $rs | "\($rs[0].target)/\($rs[0].case)" as $id
     | ($rs | arm("base")) as $b | ($rs | arm("cand")) as $c | select(($c | length) > 0)
     # Each --json file carries the plurality of its own pass. An arm may have
     # several files, and the case holds only when it passes in every one.
     | ($c | all(.pass)) as $cpass | (if ($b | length) > 0 then ($b | all(.pass)) else null end) as $bpass
     | if $cpass == false and $bpass != false then "REJECT unit \($id): the candidate answers \($c | map(select(.pass == false)) | .[0].verdict), and the case expects \($c[0].expected) (\($c | right)/\($c | length) votes)"
       elif $cpass == true and $bpass == false then "GAIN unit \($id): the baseline failed the case, and the candidate passes it (\($c | right)/\($c | length) votes)"
       elif ($b | length) == 0 then empty
       else (($c | right) / ($c | length) - ($b | right) / ($b | length)) as $d | ([($b | length), ($c | length)] | min) as $n
         | if $d == 0 then empty
           elif $n < $votes and $d < 0 then "UNDECIDED unit \($id): the tally fell from \($b | right)/\($b | length) to \($c | right)/\($c | length) with no flip. Run this case at --votes \($votes) on both arms."
           elif $n < $votes then "NOTE unit \($id): the tally rose from \($b | right)/\($b | length) to \($c | right)/\($c | length). It counts as a gain only at --votes \($votes)."
           elif ($d * $n | runs) <= -$move then "REJECT unit \($id): the tally fell from \($b | right)/\($b | length) to \($c | right)/\($c | length)"
           elif ($d * $n | runs) >= $move then "GAIN unit \($id): the tally rose from \($b | right)/\($b | length) to \($c | right)/\($c | length)"
           else "NOTE unit \($id): \($b | right)/\($b | length) baseline and \($c | right)/\($c | length) candidate votes, which is inside the noise" end
       end),
    ([arm("base"), arm("cand")] | map(map(.cost_usd) | add // 0 | . * 100 | round / 100) | select(.[1] > 0)
     | "PRICE unit: \(.[0]) dollars for the baseline runs and \(.[1]) dollars for the candidate runs")
' <<<"$UNIT" >> "$FINDINGS"

before=$(size_words "$REF" prose); after=$(size_words tree prose)
code_before=$(size_words "$REF" code); code_after=$(size_words tree code)
say "PRICE size: the shipped prose has $after words, and it had $before at $REF ($((after - before))). The shipped code has $code_after, and it had $code_before ($((code_after - code_before)))."
if [ "$after" -gt "$before" ] && ! grep -q '^GAIN ' "$FINDINGS"; then
    say "REJECT size: the candidate grows the shipped prose by $((after - before)) words, and no measured outcome moved up. Prose that grows must show its gain."
fi

sort -s -k1,1 "$FINDINGS" | sed 's/^/  /'
if grep -q '^REJECT ' "$FINDINGS"; then echo "verdict: reject"; exit 1; fi
if grep -q '^UNDECIDED' "$FINDINGS"; then echo "verdict: undecided"; exit 3; fi
echo "verdict: accept"
