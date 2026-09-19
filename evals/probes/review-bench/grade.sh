#!/bin/bash
# Grade one review-bench review, or prove the grader against fixed text.
#
# Usage:
#   bash grade.sh <run-dir>     write <run-dir>/result.json
#   bash grade.sh --self-check  fixed reviews over fixed metas: one that names
#                               the defect and one that does not, the answer
#                               shapes a reviewer uses, and the two variants of
#                               a directory fixture, whose defect meta carries
#                               the case regex and whose clean meta carries a
#                               regex nothing matches. That last pair reads the
#                               shipped regex of fixtures/live-array, so a
#                               regex that stops naming its defect fails here.
#                               No model call, no cost.
#
# It reads <run-dir>/envelope.json (the `--output-format json` envelope of the
# nested `claude -p`), <run-dir>/brief.md, and <run-dir>/run.json, and writes:
#
#   caught          the review's own text matches the case regex. The regex
#                   holds words of a *finding*, never of the code, because the
#                   brief carries the diff.
#   brief_named     the brief already matched it. A review that repeats its
#                   brief caught nothing, so a catch counts only where this
#                   reads `no`. This mirrors `review_named` in evals/lab.
#   severity        the severity word nearest the matching line.
#   findings_count  how many findings the review reported, counted by its own
#                   severity markers. Mechanical, and an upper bound.
#   false_alarms    on a clean change, findings_count until a person judges it.
#                   A finding there is a false alarm when it claims a defect
#                   that no input can reach, or one the Plan never asked for. A
#                   true remark about a reachable weakness is not a false
#                   alarm: it is a bug in the fixture, and the fixture is what
#                   gets fixed.
#   cost_usd        the envelope's total_cost_usd.
#   seconds         wall clock, from run.json.
#   spawned         entries in the nested session's subagents directory. The
#                   envelope's own subagent_stats reads 0 on a complete review,
#                   so the directory is the only count there is.
#   indeterminate   no envelope, unparseable, or is_error. Never a miss.
#
# A regex lies both ways, so every hit and every miss wants a person's eye.
# Where a person has read one, they write <run-dir>/judged.json with any of
# `caught`, `severity`, `false_alarms`, `false_alarms_list` or `note`, and
# those fields win over the mechanical ones. result.json records `judged`.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
SEV_RE='critical|high|medium|moderate|low|minor|major|blocker|nit'

# count_findings FILE: how many findings the review reported. The reviewer
# answers in whatever shape it likes, so this tries four shapes in turn and
# takes the first that finds anything. It is an upper bound and a person's
# reading decides a false alarm.
count_findings() {
    local f=$1 n
    # A JSON array of finding objects, fenced or bare.
    n=$(sed -n '/^```json/,/^```$/p' "$f" | sed '1d;$d' \
        | jq 'if type == "array" then length else 0 end' 2>/dev/null | head -1)
    [ "${n:-0}" -gt 0 ] 2>/dev/null && { echo "$n"; return; }
    n=$(jq 'if type == "array" then length else 0 end' "$f" 2>/dev/null)
    [ "${n:-0}" -gt 0 ] 2>/dev/null && { echo "$n"; return; }
    # A severity or impact label per finding.
    n=$(grep -ciE "^[[:space:]]*([-*#>]|[0-9]+[.)])?[[:space:]]*(\*\*)?(severity|impact)(\*\*)?[[:space:]]*:" "$f" 2>/dev/null)
    [ "${n:-0}" -gt 0 ] && { echo "$n"; return; }
    # A list item that names a file or a line. A fixture nests its files, so a
    # finding may cite `reports/top.js` without the top directory.
    n=$(grep -ciE "^[[:space:]]*([-*]|[0-9]+[.)])[[:space:]].*(src/|tests/|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.js|\.js:[0-9])" "$f" 2>/dev/null)
    [ "${n:-0}" -gt 0 ] && { echo "$n"; return; }
    # A heading per finding.
    grep -ciE "^#{2,4}[[:space:]]+" "$f" 2>/dev/null
}

# severity_near FILE REGEX: the severity word on or near the first line that
# matches REGEX. Looks at the 12 lines above it and the 6 below, which is
# where a finding keeps its own label.
severity_near() {
    local line
    line=$(grep -niE "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1)
    [ -z "$line" ] && return
    local from=$((line > 12 ? line - 12 : 1)) to=$((line + 6))
    sed -n "${from},${to}p" "$1" 2>/dev/null \
        | grep -oiE "\b($SEV_RE)\b" | head -1 | tr 'A-Z' 'a-z'
}

# spawned_count SESSION_ID: the nested session's subagent transcripts.
spawned_count() {
    local d
    [ -z "${1:-}" ] || [ "$1" = null ] && { echo 0; return; }
    d=$(find "$HOME/.claude/projects" -maxdepth 3 -type d -path "*/$1/subagents" 2>/dev/null | head -1)
    [ -z "$d" ] && { echo 0; return; }
    # One subagent leaves a transcript and a meta file. Count the transcripts.
    find "$d" -maxdepth 1 -type f -name '*.jsonl' | wc -l
}

grade_one() {
    local rd=$1 env="$1/envelope.json" regex clean ind=false
    [ -f "$rd/run.json" ] || { echo "grade: no run.json in $rd" >&2; return 1; }
    regex=$(jq -r .meta.regex "$rd/run.json")
    clean=$(jq -r .meta.clean "$rd/run.json")

    local is_error subtype session cost result
    if [ ! -s "$env" ] || ! jq -e . "$env" >/dev/null 2>&1; then
        ind=true; is_error=null; subtype=null; session=null; cost=0; result=""
    else
        # `.is_error // null` answers null for `false`, because jq's `//`
        # treats false as empty. Ask whether the key is there instead.
        is_error=$(jq -r 'if has("is_error") then (.is_error | tostring) else "null" end' "$env")
        subtype=$(jq -r '.subtype // null' "$env")
        session=$(jq -r '.session_id // null' "$env")
        cost=$(jq -r '.total_cost_usd // 0' "$env")
        jq -r '.result // ""' "$env" > "$rd/review.txt"
        result=$(cat "$rd/review.txt")
        { [ "$is_error" != false ] || [ "$subtype" != success ] || [ -z "$result" ]; } && ind=true
    fi
    [ -f "$rd/review.txt" ] || : > "$rd/review.txt"

    local caught=no told=no sev="" n=0
    if [ "$ind" = false ]; then
        grep -qiE "$regex" "$rd/review.txt" && caught=yes
        sev=$(severity_near "$rd/review.txt" "$regex")
        n=$(count_findings "$rd/review.txt"); n=${n:-0}
    fi
    grep -qiE "$regex" "$rd/brief.md" 2>/dev/null && told=yes

    local fa=null
    [ "$clean" = true ] && [ "$ind" = false ] && fa=$n

    jq -n --slurpfile run "$rd/run.json" \
        --arg caught "$caught" --arg told "$told" --arg sev "$sev" \
        --argjson n "$n" --argjson fa "$fa" --argjson ind "$ind" \
        --argjson cost "${cost:-0}" \
        --argjson spawned "$(spawned_count "$session")" \
        --arg session "$session" --arg is_error "$is_error" --arg subtype "$subtype" \
        '$run[0] + {
            caught: $caught, brief_named: $told,
            severity: (if $sev == "" then null else $sev end),
            findings_count: $n, false_alarms: $fa, false_alarms_list: [],
            clean: $run[0].meta.clean, kind: $run[0].meta.kind,
            indeterminate: $ind, cost_usd: $cost, spawned: $spawned,
            seconds: ($run[0].seconds // 0),
            session_id: $session, is_error: $is_error, subtype: $subtype,
            judged: false
        }' > "$rd/result.json" || return 1

    # A person's reading wins over the regex, in both directions.
    if [ -f "$rd/judged.json" ]; then
        jq -s '.[0] + .[1] + {judged: true}' "$rd/result.json" "$rd/judged.json" > "$rd/result.json.t" \
            && mv "$rd/result.json.t" "$rd/result.json"
    fi
    jq -r '"grade: \(.target) \(.config) v\(.vote): caught=\(.caught) brief_named=\(.brief_named) findings=\(.findings_count) $\(.cost_usd) \(.seconds)s spawned=\(.spawned)\(if .indeterminate then " INDETERMINATE" else "" end)"' "$rd/result.json"
}

# --- the self-check --------------------------------------------------------

self_check() {
    local tmp rc=0
    tmp=$(mktemp -d) || return 1
    local regex='off.by.one|allows? one (too many|more)'
    # mk NAME REVIEW [REGEX] [CLEAN]: one run directory to grade.
    mk() {
        local d="$tmp/$1"; mkdir -p "$d"
        jq -n --arg re "${3:-$regex}" --argjson cl "${4:-false}" \
            '{target: "self", id: "self", variant: "neutral",
            config: "X", model: "none", vote: 1, level: "high", seconds: 7,
            meta: {id: "self", kind: "boundary", clean: $cl, regex: $re}}' > "$d/run.json"
        printf 'The Plan adds a cap check.\n' > "$d/brief.md"
        jq -n --arg r "$2" '{is_error: false, subtype: "success", session_id: "s-0",
            total_cost_usd: 0.25, result: $r}' > "$d/envelope.json"
        echo "$d"
    }
    local hit miss
    hit=$(mk hit '## Findings

### 1. The daily cap allows one too many calls
**Severity:** high

The comparison lets a key make a call when it has already used its whole cap.')
    miss=$(mk miss '## Findings

### 1. The new function has no JSDoc
**Severity:** low

Style only. Nothing else stood out in this change.')
    grade_one "$hit" >/dev/null
    grade_one "$miss" >/dev/null
    local a b s f
    a=$(jq -r .caught "$hit/result.json"); b=$(jq -r .caught "$miss/result.json")
    s=$(jq -r .severity "$hit/result.json"); f=$(jq -r .findings_count "$hit/result.json")
    [ "$a" = yes ] && echo "ok   a review that names the defect grades caught" \
        || { echo "FAIL a review that names the defect graded $a"; rc=1; }
    [ "$b" = no ] && echo "ok   a review that misses it grades missed" \
        || { echo "FAIL a review that misses it graded $b"; rc=1; }
    [ "$s" = high ] && echo "ok   the severity beside the finding is read off" \
        || { echo "FAIL the severity read off as $s"; rc=1; }
    [ "$f" = 1 ] && echo "ok   one finding is counted as one" \
        || { echo "FAIL one finding counted as $f"; rc=1; }
    # The reviewer answers in more than one shape. A fenced JSON array of
    # findings must count as its own length, and it must still grade caught.
    local json
    json=$(mk json '```json
[
  {"file": "src/usage.js", "summary": "allowCall allows one too many calls: it should compare with strict less than."},
  {"file": "tests/quota.test.js", "summary": "Nothing tests the exact boundary."}
]
```')
    grade_one "$json" >/dev/null
    [ "$(jq -r '.caught + "/" + (.findings_count | tostring)' "$json/result.json")" = yes/2 ] \
        && echo "ok   a JSON answer grades caught and counts its findings" \
        || { echo "FAIL a JSON answer graded $(jq -c '[.caught, .findings_count]' "$json/result.json")"; rc=1; }
    # A brief that names the defect must show brief_named=yes, whatever the
    # review said. That is the measure the lab counts a catch over.
    printf 'The Plan adds a cap check that allows one too many calls.\n' > "$hit/brief.md"
    grade_one "$hit" >/dev/null
    [ "$(jq -r .brief_named "$hit/result.json")" = yes ] \
        && echo "ok   a brief that names the defect grades brief_named=yes" \
        || { echo "FAIL a brief that names the defect did not"; rc=1; }
    # A person's reading wins over the regex.
    jq -n '{caught: "no", note: "the finding is about another line"}' > "$miss/judged.json"
    jq -n '{caught: "yes", note: "named in prose the regex misses"}' > "$miss/judged.json"
    grade_one "$miss" >/dev/null
    [ "$(jq -r '.caught + "/" + (.judged | tostring)' "$miss/result.json")" = yes/true ] \
        && echo "ok   a judged.json overrides the regex" \
        || { echo "FAIL judged.json did not override the regex"; rc=1; }
    # An envelope that is not a success is indeterminate, never a miss.
    jq -n '{is_error: true, subtype: "error_during_execution", session_id: "s-1"}' > "$miss/envelope.json"
    rm -f "$miss/judged.json"
    grade_one "$miss" >/dev/null
    [ "$(jq -r .indeterminate "$miss/result.json")" = true ] \
        && echo "ok   an error envelope grades indeterminate" \
        || { echo "FAIL an error envelope did not grade indeterminate"; rc=1; }
    # A directory fixture seeds two variants of one change, and the grader must
    # read them apart. The defect variant carries the case regex, the clean one
    # carries `a^`, which nothing matches, and its findings are its false
    # alarms. The regex here is the shipped one, so this also holds it to a
    # review that names the defect and to one that does not.
    local case_meta="$DIR/fixtures/live-array/meta.json"
    if [ ! -f "$case_meta" ]; then
        echo "FAIL fixtures/live-array/meta.json is missing, so the two variants go unchecked"; rc=1
    else
        local case_re named generic dfct cln gen
        case_re=$(jq -r .regex "$case_meta")
        named='## Findings

### 1. topByPriority reorders the tickets the store holds
**Severity:** high

src/reports/top.js sorts the array that store.all() hands back, and that array
is the one the store keeps. After a dashboard call, nextInQueue() in
src/queue.js no longer serves the ticket that has waited longest.'
        generic='## Findings

- reports/top.js: topByAge has no JSDoc, and its default of 5 is undocumented.
- tests/reports/top.test.js: nothing asserts what a request for zero gives.'
        dfct=$(mk dir-defect "$named" "$case_re" false)
        cln=$(mk dir-clean "$named" 'a^' true)
        gen=$(mk dir-generic "$generic" "$case_re" false)
        grade_one "$dfct" >/dev/null
        grade_one "$cln" >/dev/null
        grade_one "$gen" >/dev/null
        [ "$(jq -r '.caught + "/" + (.clean | tostring)' "$dfct/result.json")" = yes/false ] \
            && echo "ok   the defect variant grades caught against the case regex" \
            || { echo "FAIL the defect variant graded $(jq -c '[.caught, .clean]' "$dfct/result.json")"; rc=1; }
        [ "$(jq -r '.caught + "/" + (.false_alarms | tostring)' "$cln/result.json")" = no/1 ] \
            && echo "ok   the clean variant catches nothing and counts its finding as a false alarm" \
            || { echo "FAIL the clean variant graded $(jq -c '[.caught, .false_alarms]' "$cln/result.json")"; rc=1; }
        [ "$(jq -r '.caught + "/" + (.findings_count | tostring)' "$gen/result.json")" = no/2 ] \
            && echo "ok   a generic review over nested paths grades missed and counts two findings" \
            || { echo "FAIL a generic review graded $(jq -c '[.caught, .findings_count]' "$gen/result.json")"; rc=1; }
    fi
    rm -rf "$tmp"
    [ "$rc" = 0 ] && echo "grade: self-check green" || echo "grade: self-check RED"
    return "$rc"
}

case "${1:-}" in
    --self-check) self_check ;;
    -h|--help|"") sed -n '2,44p' "$0" ;;
    *) grade_one "${1%/}" ;;
esac
