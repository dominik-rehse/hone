#!/bin/bash
# The review-bench probe: what does the nested `/code-review` catch, and what
# does each reviewer cost?
#
# hone's run loop reuses Claude Code's built-in `/code-review` through a nested
# headless `claude -p` (step 5 of `skills/run/SKILL.md`). Nothing measured its
# catch rate. Every lab run that carries the measure had `brief_named=yes`, so
# the review was handed its finding. This probe takes the reviewer out of the
# loop and puts it in front of fixed diffs with planted defects and a brief that
# never names them.
#
# One job is one review. It copies a fixture from seed.sh, applies the change to
# the working tree of a copy on `main`, and runs the skill's own command from
# inside that copy, with the skill's own allowlist and level. Then grade.sh
# writes result.json. The only additions to the command are a dollar cap and a
# wall-clock cap, because this probe runs it dozens of times.
#
# Configurations (--config, repeatable):
#   A  claude-opus-5          the pin as skills/run/SKILL.md has it.
#   B  claude-sonnet-5        the same command, another review model.
#   C  claude-haiku-4-5-20251001
# The built-in command picks its recipe by the review model, so A and B are two
# reviewers and not one reviewer on two models.
#
# A target is a fixture id, or a fixture id and a variant after a colon. Every
# brief seed.sh wrote is one target: `boundary` for a fixture with one brief,
# `carve-out:justified` for its second brief, and `live-array:defect` with
# `live-array:clean` for a directory fixture's two repositories. seed.sh has
# the fixture shapes.
#
# A directory fixture whose change carries several defects has one meta with a
# `defects` list instead of a case regex. Its targets are the same two, and one
# review of it is graded against each defect on its own, so `caught` reads as a
# tally like `2/3` and the summary gets a table of catch rate per defect.
#
# Usage:
#   bash evals/probes/review-bench/run.sh [--config A|B|C] [--case PATTERN]
#        [--votes N] [--jobs N] [--budget USD] [--total USD] [--timeout MIN]
#        [--out DIR] [--seed] [--grade-only] [--summary] [--dry-run]
#   --config X     which reviewer. Repeatable. Default A.
#   --case PATTERN a target, or a shell glob over the targets: `live-array:*`
#                  is the pilot pair alone, `*:defect` every defect variant.
#                  Repeatable. A pattern that matches nothing is fatal.
#                  Default every target.
#   --votes N      reviews per target and configuration (default 1).
#   --jobs N       reviews at the same time (default 3).
#   --budget USD   the cap of one review, passed to `claude --max-budget-usd`
#                  (default 1.5).
#   --total USD    the cap of the whole pass (default 20). A wave starts only
#                  when the spend so far plus its worst case stays under it.
#                  The spend so far counts every review already under
#                  --out, and the worst case is --budget per review.
#   --timeout MIN  the wall-clock cap of one review (default 15).
#   --out DIR      the output root (default /var/tmp/hone-probe/review-bench,
#                  or $PROBE_OUT). It must sit outside every project: Claude
#                  Code reads CLAUDE.md and .claude/rules/ from every directory
#                  above the working directory, and a reviewer that finds
#                  hone's own rules is not reviewing the fixture.
#   --seed         run seed.sh first. Do this whenever a fixture changed.
#   --grade-only   re-grade the runs already on disk. No model call, no cost.
#   --summary      write summary.md over the runs on disk and stop.
#   --dry-run      list the jobs and stop.
#
# Output goes to $OUT/runs/<id>-<variant>-<config>-v<n>/: repo/ is the fixture with
# the change in its working tree, brief.md is what the reviewer was given,
# envelope.json is the `--output-format json` envelope, review.txt is its
# `.result`, run.json is what the run was, and result.json is the grade.
# summary.md sits at $OUT/summary.md.
#
# A run whose envelope is missing, unparseable, or `is_error: true` is
# indeterminate, and the summary counts it apart. It never counts as a miss.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OUT=${PROBE_OUT:-/var/tmp/hone-probe/review-bench}
CONFIGS=() TARGETS=() VOTES=1 JOBS=3 BUDGET=1.5 TOTAL=20 TIMEOUT=15
DO_SEED=no GRADE_ONLY=no SUMMARY_ONLY=no DRY=no

while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIGS+=("$2"); shift 2 ;;
        --case) TARGETS+=("$2"); shift 2 ;;
        --votes) VOTES=$2; shift 2 ;;
        --jobs) JOBS=$2; shift 2 ;;
        --budget) BUDGET=$2; shift 2 ;;
        --total) TOTAL=$2; shift 2 ;;
        --timeout) TIMEOUT=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        --seed) DO_SEED=yes; shift ;;
        --grade-only) GRADE_ONLY=yes; shift ;;
        --summary) SUMMARY_ONLY=yes; shift ;;
        --dry-run) DRY=yes; shift ;;
        -h|--help) sed -n '2,71p' "$0"; exit 0 ;;
        *) echo "run: unknown argument $1" >&2; exit 2 ;;
    esac
done
[ ${#CONFIGS[@]} -eq 0 ] && CONFIGS=(A)

# The model of each configuration. An alias floats, so these are full IDs, as
# the pin in skills/run/SKILL.md is.
model_of() {
    case "$1" in
        A) echo claude-opus-5 ;;
        B) echo claude-sonnet-5 ;;
        C) echo claude-haiku-4-5-20251001 ;;
        *) echo "run: unknown configuration $1" >&2; exit 2 ;;
    esac
}

FIX="$OUT/fixtures"
RUNS="$OUT/runs"

# The output root must not sit under a project, or every reviewer reads that
# project's CLAUDE.md and rules instead of the fixture alone.
d=$OUT
while [ "$d" != "/" ] && [ -n "$d" ]; do
    for f in CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md .claude/rules; do
        [ -e "$d/$f" ] && { echo "run: $d/$f sits above the output root" >&2; exit 2; }
    done
    d=$(dirname "$d")
done

[ "$DO_SEED" = yes ] && { bash "$DIR/seed.sh" --out "$OUT" || exit 1; }
[ -d "$FIX" ] || { echo "run: no fixtures under $FIX. Run with --seed." >&2; exit 2; }

# Every brief seed.sh wrote is one target. brief.md is the bare id, and
# brief-<variant>.md is `<id>:<variant>`.
ALL=()
for d in "$FIX"/*/; do
    id=$(basename "$d")
    [ -f "$d/brief.md" ] && ALL+=("$id")
    for b in "$d"brief-*.md; do
        [ -e "$b" ] || continue
        v=$(basename "$b" .md)
        ALL+=("$id:${v#brief-}")
    done
done

if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=("${ALL[@]}")
else
    picked=()
    for pat in "${TARGETS[@]}"; do
        hit=no
        for t in "${ALL[@]}"; do
            # shellcheck disable=SC2254  # the pattern is meant to glob
            case "$t" in $pat) picked+=("$t"); hit=yes ;; esac
        done
        [ "$hit" = no ] && { echo "run: no target matches $pat" >&2; exit 2; }
    done
    TARGETS=("${picked[@]}")
fi

mkdir -p "$RUNS" || exit 1

# --- the summary -----------------------------------------------------------

write_summary() {
    local f="$OUT/summary.md" r
    {
        echo "# review-bench"
        echo
        echo "Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) from $RUNS."
        echo
        echo "| target | kind | config | model | vote | brief_named | caught | severity | findings | cost | s | spawned |"
        echo "|---|---|---|---|---|---|---|---|---|---|---|---|"
        for r in "$RUNS"/*/result.json; do
            [ -e "$r" ] || continue
            jq -r '"| \(.target) | \(.kind) | \(.config) | \(.model) | \(.vote) | \(.brief_named) | \(.caught) | \(.severity // "-") | \(.findings_count) | \(.cost_usd) | \(.seconds) | \(.spawned) |"' "$r"
        done
        echo
        echo "## Catch rate per kind and configuration"
        echo
        echo "| kind | brief | config | reviews | caught | rate |"
        echo "|---|---|---|---|---|---|"
        jq -rs '[.[] | select(.clean == false and .indeterminate == false
                              and (.meta | has("defects") | not))]
                | group_by(.kind + "/" + .variant + "/" + .config)[]
                | "| \(.[0].kind) | \(.[0].variant) | \(.[0].config) | \(length) | \([.[] | select(.caught == "yes")] | length) | \(((([.[] | select(.caught == "yes")] | length) * 100 / length) | floor))% |"' \
            "$RUNS"/*/result.json 2>/dev/null
        echo
        echo "## Catch rate per defect of a multi-defect fixture"
        echo
        echo "| target | defect | config | reviews | caught | rate |"
        echo "|---|---|---|---|---|---|"
        jq -rs '[.[] | select(.clean == false and .indeterminate == false
                              and (.meta | has("defects")))]
                | [.[] as $r | $r.meta.defects[]
                   | {target: $r.target, config: $r.config, defect: .id,
                      caught: ($r["caught_" + .id] // "no")}]
                | group_by(.target + "/" + .defect + "/" + .config)[]
                | "| \(.[0].target) | \(.[0].defect) | \(.[0].config) | \(length) | \([.[] | select(.caught == "yes")] | length) | \(((([.[] | select(.caught == "yes")] | length) * 100 / length) | floor))% |"' \
            "$RUNS"/*/result.json 2>/dev/null
        echo
        echo "## False alarms on the clean changes"
        echo
        echo "| target | config | reviews | findings (mechanical) | false alarms (judged) |"
        echo "|---|---|---|---|---|"
        jq -rs '[.[] | select(.clean == true and .indeterminate == false)]
                | group_by(.target + "/" + .config)[]
                | "| \(.[0].target) | \(.[0].config) | \(length) | \([.[] | .findings_count] | add) | \([.[] | .false_alarms // 0] | add) |"' \
            "$RUNS"/*/result.json 2>/dev/null
        echo
        echo "## Cost and time per configuration"
        echo
        echo "| config | model | reviews | total \$ | mean \$ | mean s | mean spawned |"
        echo "|---|---|---|---|---|---|---|"
        jq -rs '[.[] | select(.indeterminate == false)] | group_by(.config)[]
                | "| \(.[0].config) | \(.[0].model) | \(length) | \((([.[] | .cost_usd] | add) * 1000 | round) / 1000) | \((([.[] | .cost_usd] | add) / length * 1000 | round) / 1000) | \((([.[] | .seconds] | add) / length) | round) | \((([.[] | .spawned] | add) / length * 10 | round) / 10) |"' \
            "$RUNS"/*/result.json 2>/dev/null
        echo
        local ind
        ind=$(jq -rs '[.[] | select(.indeterminate == true)] | length' "$RUNS"/*/result.json 2>/dev/null)
        echo "Indeterminate reviews: ${ind:-0}."
    } > "$f"
    echo "run: summary at $f"
}

[ "$SUMMARY_ONLY" = yes ] && { write_summary; exit 0; }

if [ "$GRADE_ONLY" = yes ]; then
    for d in "$RUNS"/*/; do
        [ -f "$d/run.json" ] && bash "$DIR/grade.sh" "$d"
    done
    write_summary
    exit 0
fi

# --- one review ------------------------------------------------------------

# prepare TARGET CONFIG VOTE -> prints the run directory, or nothing.
prepare() {
    local target=$1 config=$2 vote=$3
    local id=${target%%:*} variant=${target#*:}
    [ "$variant" = "$target" ] && variant=neutral
    # A directory fixture keeps a repository and a meta per variant. A heredoc
    # fixture keeps one of each for all of its briefs.
    local fd="$FIX/$id" repo brief meta
    repo="$fd/repo-$variant"; [ -d "$repo" ] || repo="$fd/repo"
    brief="$fd/brief-$variant.md"; [ -f "$brief" ] || brief="$fd/brief.md"
    meta="$fd/meta-$variant.json"; [ -f "$meta" ] || meta="$fd/meta.json"
    local rd="$RUNS/${id}-${variant}-${config}-v${vote}"
    rm -rf "$rd" && mkdir -p "$rd" || return 1
    cp -a "$repo" "$rd/repo" || return 1
    cp "$brief" "$rd/brief.md" || return 1
    # The reviewer sees what a worktree at step 5 shows: the change in the
    # working tree over the primary branch. `--index` stages the new files, so
    # `git diff HEAD` holds the whole change and nothing is untracked.
    git -C "$rd/repo" checkout -q main || return 1
    git -C "$rd/repo" diff main..change | git -C "$rd/repo" apply --index || return 1
    git -C "$rd/repo" branch -q -D change || return 1
    jq -n --arg target "$target" --arg id "$id" --arg variant "$variant" \
        --arg config "$config" --arg model "$(model_of "$config")" \
        --argjson vote "$vote" --arg level high --arg budget "$BUDGET" \
        --arg claude "$(claude --version 2>/dev/null)" \
        --arg hone "$(jq -r .version "$DIR/../../../.claude-plugin/plugin.json" 2>/dev/null)" \
        --argjson meta "$(cat "$meta")" \
        '{target: $target, id: $id, variant: $variant, config: $config,
          model: $model, vote: $vote, level: $level, budget_usd: ($budget | tonumber),
          claude: $claude, hone: $hone, meta: $meta}' > "$rd/run.json" || return 1
    echo "$rd"
}

# review RUNDIR: the skill's command, with a dollar cap and a time cap.
review() {
    local rd=$1 model started ended
    model=$(jq -r .model "$rd/run.json")
    started=$(date +%s)
    (
        cd "$rd/repo" && timeout "${TIMEOUT}m" claude -p "/code-review high $(cat "$rd/brief.md")" \
            --allowedTools "Task Agent Read Grep Glob Bash(git *)" \
            --model "$model" --effort high \
            --max-budget-usd "$BUDGET" \
            --output-format json > "$rd/envelope.json.part" 2>&1
    )
    mv "$rd/envelope.json.part" "$rd/envelope.json" 2>/dev/null
    ended=$(date +%s)
    jq --argjson s "$((ended - started))" '. + {seconds: $s}' "$rd/run.json" > "$rd/run.json.t" \
        && mv "$rd/run.json.t" "$rd/run.json"
    bash "$DIR/grade.sh" "$rd" >/dev/null
}

# --- the waves -------------------------------------------------------------

jobs_list=()
for config in "${CONFIGS[@]}"; do
    model_of "$config" >/dev/null
    for target in "${TARGETS[@]}"; do
        v=1
        while [ "$v" -le "$VOTES" ]; do
            jobs_list+=("$target|$config|$v")
            v=$((v + 1))
        done
    done
done

if [ "$DRY" = yes ]; then
    printf '%s\n' "${jobs_list[@]}"
    echo "run: ${#jobs_list[@]} reviews, worst case \$$(echo "${#jobs_list[@]} * $BUDGET" | bc)"
    exit 0
fi

spent() {
    jq -rs '[.[] | .cost_usd // 0] | add // 0' "$RUNS"/*/result.json 2>/dev/null || echo 0
}

i=0
while [ "$i" -lt "${#jobs_list[@]}" ]; do
    wave=("${jobs_list[@]:i:JOBS}")
    so_far=$(spent)
    worst=$(echo "$so_far + ${#wave[@]} * $BUDGET" | bc)
    if [ "$(echo "$worst > $TOTAL" | bc)" = 1 ]; then
        echo "run: stopping before the next wave. Spent \$$so_far, worst case \$$worst, cap \$$TOTAL." >&2
        break
    fi
    pids=()
    for job in "${wave[@]}"; do
        IFS='|' read -r target config vote <<< "$job"
        rd=$(prepare "$target" "$config" "$vote") || { echo "run: could not prepare $job" >&2; continue; }
        echo "run: $target $config v$vote -> $rd"
        review "$rd" &
        pids+=($!)
    done
    for p in "${pids[@]}"; do wait "$p"; done
    i=$((i + JOBS))
done

write_summary
echo "run: spent \$$(spent) over $(find "$RUNS" -name result.json | wc -l) reviews"
