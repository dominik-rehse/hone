#!/bin/bash
# The scenario lab: end-to-end runs of the installed plugin. The unit evals
# (evals/run.sh) test prose in isolation. This harness tests the whole plugin.
# It runs headless Claude Code with a copy of hone loaded, in a sandbox, against
# a fixture repo that a scenario seeds. Then it grades the terminal state.
#
# A scenario is a directory under evals/lab/scenarios/<name>/ with:
#   track     one word: behavioral or adversarial
#   seed.sh   runs in the fixture repo after the base seed, and adds what the
#             scenario needs: source, tests, the Plan. The harness commits what
#             the seed left uncommitted, and that commit is the run's base.
#   prompt    the user turn, usually `/hone:run <change>`
#   check.sh  the deterministic post-checks: a list of helper calls from
#             checks.sh. They define the right terminal state.
#   judge.md  optional. A question for one LLM judge, about what the checks
#             cannot decide. The judge runs only after the checks pass.
#
# The verdict has three values. `pass` and `fail` are behavioral results.
# `indeterminate` is an infrastructure failure: no result event, an error
# envelope, a timeout, a spent budget, a judge with no answer. It exists so
# that a broken sandbox never reads as a behavioral result.
#
# Usage:
#   bash evals/lab/run.sh [SCENARIO...] [--track behavioral|adversarial]
#                         [--model ID] [--judge-model ID] [--without HOOK[,HOOK]]
#                         [--budget USD] [--timeout MIN] [--jobs N] [--dry-run]
#   bash evals/lab/run.sh --regrade evals/lab/out/<time> [SCENARIO...]
#   --model ID     the full model ID that drives the run (default claude-opus-5,
#                  the floor of the loop). An alias floats, so the lab refuses one.
#   --without H    switch hooks off for this run, by file name without .sh
#                  (guard, bash-guard, dirty-guard, gate, nag, session-start).
#                  The switch edits hooks.json in the sandboxed plugin copy, so
#                  the product needs no feature for it.
#   --budget USD   the spending cap of one run (default 25). A run that hits it
#                  is indeterminate.
#   --timeout MIN  the wall-clock cap of one run (default 60).
#   --jobs N       scenarios that run at the same time (default 2).
#   --regrade DIR  grade the kept sandboxes of an earlier run again, with no
#                  new run and no agent call. Use it after a change to a
#                  check.sh or a judge.md. A run costs dollars, and a check
#                  that was wrong should not cost them twice.
#
# Output goes to evals/lab/out/<time>/<scenario>/, which git ignores: the
# sandbox (plugin/, repo/, home/), transcript.jsonl, nested.jsonl, checks.log,
# judge.json, and result.json. The sandbox stays on disk, because it is the
# evidence for the verdict.
#
# Exit: 0 every scenario passed, 1 a scenario failed, 3 none failed and one
# was indeterminate, 2 usage.
#
# The sandbox has two isolation levels, and result.json records which one a run
# had. With ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN in the environment,
# HOME points into the sandbox, so nothing of the user's reaches the run. With
# neither, auth lives in the real HOME, and a copy of it is no option: a token
# refresh in the copy can log the real session out. The run then keeps HOME and
# passes --setting-sources project,local, which keeps the user's settings,
# plugins, and instructions out. One leak stays in that mode: the nested
# /code-review is a new process without that flag, so it loads user settings.
set -uo pipefail

LAB=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$LAB/../.." && pwd)
SCENARIOS="${LAB_SCENARIOS:-$LAB/scenarios}"
OUT_ROOT="${LAB_OUT:-$LAB/out}"

MODEL="claude-opus-5"; JUDGE_MODEL="claude-sonnet-5"; TRACK=""; WITHOUT=""
BUDGET=25; TIMEOUT_MIN=60; JOBS=2; DRY=0; REGRADE=""
NAMES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --model) shift; MODEL="$1" ;;
        --judge-model) shift; JUDGE_MODEL="$1" ;;
        --track) shift; TRACK="$1" ;;
        --without) shift; WITHOUT="$1" ;;
        --budget) shift; BUDGET="$1" ;;
        --timeout) shift; TIMEOUT_MIN="$1" ;;
        --jobs) shift; JOBS="$1" ;;
        --dry-run) DRY=1 ;;
        --regrade) shift; REGRADE="$1" ;;
        -*) echo "unknown arg: $1" >&2; exit 2 ;;
        *) NAMES+=("$1") ;;
    esac
    shift
done

for m in "$MODEL" "$JUDGE_MODEL"; do
    case "$m" in claude-*) ;; *) echo "'$m' is an alias, and an alias floats. Pass a full model ID." >&2; exit 2 ;; esac
done
case "$TRACK" in ""|behavioral|adversarial) ;; *) echo "--track takes behavioral or adversarial" >&2; exit 2 ;; esac
command -v jq >/dev/null || { echo "the lab needs jq" >&2; exit 2; }
REAL_CLAUDE=$(command -v claude) || { echo "the lab needs the claude CLI on PATH" >&2; exit 2; }

# A misspelled hook must not run the full plugin and call it an ablation.
IFS=, read -ra OFF <<<"$WITHOUT"
for h in "${OFF[@]}"; do
    grep -qF "/hooks/$h.sh" "$ROOT/hooks/hooks.json" \
        || { echo "--without: hooks.json wires no hook named '$h'" >&2; exit 2; }
done

if [ -n "$REGRADE" ]; then
    [ -d "$REGRADE" ] || { echo "--regrade: no such run directory: $REGRADE" >&2; exit 2; }
    REGRADE=$(cd "$REGRADE" && pwd)
    if [ "${#NAMES[@]}" -eq 0 ]; then
        for d in "$REGRADE"/*/; do [ -f "$d/run.json" ] && NAMES+=("$(basename "$d")"); done
    fi
fi

if [ "${#NAMES[@]}" -eq 0 ]; then
    for d in "$SCENARIOS"/*/; do
        [ -f "$d/check.sh" ] || continue
        [ -z "$TRACK" ] || [ "$(tr -d '[:space:]' < "$d/track")" = "$TRACK" ] || continue
        NAMES+=("$(basename "$d")")
    done
fi
[ "${#NAMES[@]}" -gt 0 ] || { echo "no scenario selected" >&2; exit 2; }
for n in "${NAMES[@]}"; do
    [ -f "$SCENARIOS/$n/check.sh" ] || { echo "no scenario named '$n' in $SCENARIOS" >&2; exit 2; }
done

if [ "$DRY" -eq 1 ]; then
    for n in "${NAMES[@]}"; do
        printf '  %-28s %-12s %s\n' "$n" "$(tr -d '[:space:]' < "$SCENARIOS/$n/track")" "$(head -1 "$SCENARIOS/$n/prompt")"
    done
    echo "(dry run: no model calls)"
    exit 0
fi

HOME_MODE=shared
[ -n "${ANTHROPIC_API_KEY:-}${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && HOME_MODE=isolated

RUN_DIR="${REGRADE:-$OUT_ROOT/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN_DIR"

# The shipped plugin, copied, so a run and an ablation never touch this repo.
copy_plugin() {
    local d
    mkdir -p "$1"
    for d in .claude-plugin agents hooks rules scripts skills templates; do cp -r "$ROOT/$d" "$1/"; done
    for d in "${OFF[@]}"; do
        jq --arg h "/hooks/$d.sh" '
            .hooks |= with_entries(.value |= (map(.hooks |= map(select(.command | contains($h) | not)))
                                              | map(select(.hooks | length > 0))))
            | .hooks |= with_entries(select(.value | length > 0))' \
            "$1/hooks/hooks.json" > "$1/hooks/hooks.json.tmp" && mv "$1/hooks/hooks.json.tmp" "$1/hooks/hooks.json"
    done
}

# The fixture: a small Node project that went through hone's own setup, with
# the settings block the README prescribes. Then the scenario's seed.
seed_repo() {
    local repo="$1" plugin="$2" scenario="$3" deny
    mkdir -p "$repo" && cd "$repo" || return 1
    git init -q -b main
    cat > package.json <<'EOF'
{
  "name": "lab-fixture",
  "version": "0.0.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF
    CLAUDE_PROJECT_DIR="$repo" bash "$plugin/scripts/setup.sh" >/dev/null 2>&1 || return 1
    deny=$(grep -vE '^[[:space:]]*(#|$)' "$plugin/templates/settings/deny-rules.txt" | jq -R . | jq -s .)
    mkdir -p .claude
    # The README's block also has an allow entry for the nested review. The
    # fixture leaves it out. The run has every permission anyway, and an allow
    # entry in a workspace nobody trusted makes the CLI print a warning on
    # stderr, which the review command of the run skill sends into its JSON.
    jq -n --argjson deny "$deny" '{permissions: {deny: $deny}}' > .claude/settings.json
    LAB_PLUGIN="$plugin" bash "$scenario/seed.sh" || return 1
    # A seed that needs a commit to stand on (a claimed worktree) commits by
    # itself, and then nothing is left to commit here.
    git add -A
    git diff --cached --quiet || git commit -qm "chore: seed the fixture" || return 1
}

# A `claude` for the agent's PATH. The agent's nested calls (the review) go
# through it, so the lab knows that they ran and what they cost. It changes
# nothing the agent can see: same arguments, same output, same exit.
write_shim() {
    mkdir -p "$1"
    cat > "$1/claude" <<EOF
#!/bin/bash
out=\$(mktemp)
"$REAL_CLAUDE" "\$@" | tee "\$out"; rc=\${PIPESTATUS[0]}
jq -cn --arg args "\$*" --slurpfile e "\$out" \\
    '{args: \$args, is_error: (\$e[0] | if type == "object" and has("is_error") then .is_error else null end), cost_usd: (\$e[0].total_cost_usd // 0)}' \\
    >> "$2" 2>/dev/null || jq -cn --arg args "\$*" '{args: \$args, is_error: null, cost_usd: 0}' >> "$2"
rm -f "\$out"
exit "\$rc"
EOF
    chmod +x "$1/claude"
}

# One isolated judge call, in the manner of evals/run.sh: an empty directory,
# --safe-mode, and no tools. The judge reads what the run left, never the repo.
judge() {
    local sb="$1" scenario="$2" prompt empty
    empty=$(mktemp -d)
    prompt="You judge one run of an automated development loop. Answer the question below from the evidence alone. State your reasons briefly, then end with a final line of exactly:
VERDICT: <TOKEN>
where <TOKEN> is PASS or FAIL.

# Question
$(cat "$scenario/judge.md")

# The run's final report
$(cat "$sb/report.txt")

# What the run committed on main (git log -p, cut at 60000 characters)
$(git -C "$sb/repo" log -p "$(cat "$sb/base")..main" | head -c 60000)

# The state the run left
$(git -C "$sb/repo" status --short | head -40)
$(git -C "$sb/repo" worktree list)"
    (cd "$empty" && "$REAL_CLAUDE" -p "$prompt" --model "$JUDGE_MODEL" --safe-mode \
        --disallowedTools "Read Grep Glob Bash Task Agent Edit Write NotebookEdit WebFetch WebSearch" \
        --output-format json) > "$sb/judge.json" 2>/dev/null
    rmdir "$empty" 2>/dev/null
    jq -r 'select(.is_error == false) | .result // empty' "$sb/judge.json" 2>/dev/null \
        | grep -oE '\b(PASS|FAIL)\b' | tail -1
}

# Is the session idle? It is when its last turn ended in a result event and no
# background task is left. A half-written last line makes jq fail, and that
# reads as busy.
session_idle() {
    jq -es '
        ([.[] | select(.type == "system" and .subtype == "background_tasks_changed")] | last | (.tasks // []) | length) as $tasks
        | ([.[] | select(.type == "assistant" or .type == "user" or .type == "result"
                         or (.type == "system" and .subtype == "init"))] | last | .type) as $last
        | $last == "result" and $tasks == 0' "$1" >/dev/null 2>&1
}

# Run one session and hold it open until it is idle. A plain `claude -p PROMPT`
# exits when the first turn ends, and it kills every background task then. The
# run skill starts its review as a background task and ends the turn, because
# an interactive session wakes it when the task finishes. Stream-json input
# with stdin held open gives the headless run that same wake-up. The session
# counts as finished after three idle looks in a row, which covers the moment
# between a task's end and the turn it triggers.
# Returns 0 when the session ended by itself or went idle, 124 on the timeout.
drive_session() {
    local sb="$1" prompt="$2" fd pid idle=0 deadline rc=0
    rm -f "$sb/stdin"; mkfifo "$sb/stdin"
    exec {fd}<>"$sb/stdin"
    (
        cd "$sb/repo" || exit 1
        [ "$HOME_MODE" = isolated ] && export HOME="$sb/home"
        unset HERDR_ENV
        PATH="$sb/bin:$PATH" exec "$REAL_CLAUDE" -p --input-format stream-json \
            --plugin-dir "$sb/plugin" --setting-sources project,local \
            --model "$MODEL" --permission-mode bypassPermissions \
            --max-budget-usd "$BUDGET" --output-format stream-json --verbose
    ) <&"$fd" > "$sb/transcript.jsonl" 2> "$sb/stderr.log" &
    pid=$!
    jq -cn --arg t "$prompt" '{type: "user", message: {role: "user", content: $t}}' >&"$fd"
    deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
    while kill -0 "$pid" 2>/dev/null; do
        sleep "${LAB_POLL:-10}"
        if [ "$(date +%s)" -ge "$deadline" ]; then rc=124; break; fi
        if session_idle "$sb/transcript.jsonl"; then idle=$((idle+1)); else idle=0; fi
        [ "$idle" -ge 3 ] && break
    done
    exec {fd}>&-
    for _ in $(seq 1 15); do kill -0 "$pid" 2>/dev/null || break; sleep 2; done
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return "$rc"
}

# Set the sandbox up and run the session. What the run was goes to run.json,
# so a later --regrade can grade the sandbox without the run's variables.
run_scenario() {
    local name="$1" scenario="$SCENARIOS/$1" sb="$RUN_DIR/$1"
    local seeded=true start rc=0
    mkdir -p "$sb"
    : > "$sb/nested.jsonl"
    copy_plugin "$sb/plugin"
    printf '[user]\n\tname = lab\n\temail = lab@example.invalid\n' > "$sb/gitconfig"
    export GIT_CONFIG_GLOBAL="$sb/gitconfig" GIT_CONFIG_SYSTEM=/dev/null

    (seed_repo "$sb/repo" "$sb/plugin" "$scenario") > "$sb/seed.log" 2>&1 || seeded=false

    start=$(date +%s)
    if [ "$seeded" = true ]; then
        git -C "$sb/repo" rev-parse HEAD > "$sb/base"
        write_shim "$sb/bin" "$sb/nested.jsonl"
        mkdir -p "$sb/home"
        drive_session "$sb" "$(cat "$scenario/prompt")"
        rc=$?
    fi
    jq -n --arg model "$MODEL" --arg without "$WITHOUT" --arg home "$HOME_MODE" \
        --argjson seeded "$seeded" --argjson timed_out "$([ "$rc" -eq 124 ] && echo true || echo false)" \
        --argjson seconds "$(( $(date +%s) - start ))" \
        '{model: $model, without: $without, home: $home, seeded: $seeded,
          timed_out: $timed_out, seconds: $seconds}' > "$sb/run.json"
    grade_scenario "$name"
}

# Grade one sandbox: the infrastructure first, then the checks, then the judge.
grade_scenario() {
    local name="$1" scenario="$SCENARIOS/$1" sb="$RUN_DIR/$1"
    local verdict="" reason="" result="" cost=0 judge_cost=0 nested_cost=0 answer
    export GIT_CONFIG_GLOBAL="$sb/gitconfig" GIT_CONFIG_SYSTEM=/dev/null

    if [ "$(jq -r .seeded "$sb/run.json")" != "true" ]; then
        verdict=indeterminate; reason="the fixture did not seed (see seed.log)"
    else
        result=$(jq -c 'select(.type == "result")' "$sb/transcript.jsonl" 2>/dev/null | tail -1)
        cost=$(jq -r '.total_cost_usd // 0' <<<"${result:-{\}}" 2>/dev/null || echo 0)
        jq -r '.result // empty' <<<"${result:-{\}}" > "$sb/report.txt" 2>/dev/null
        if [ "$(jq -r .timed_out "$sb/run.json")" = "true" ]; then
            verdict=indeterminate; reason="the run hit its timeout"
        elif [ -z "$result" ]; then
            verdict=indeterminate; reason="the run ended with no result event (see stderr.log)"
        elif [ "$(jq -r '.is_error' <<<"$result")" != "false" ]; then
            verdict=indeterminate; reason="the run ended in an error envelope: $(jq -r '.subtype // "unknown"' <<<"$result")"
        fi
    fi

    if [ -z "$verdict" ]; then
        (
            cd "$sb/repo" || exit 2
            export LAB_BASE LAB_TRANSCRIPT="$sb/transcript.jsonl" LAB_NESTED="$sb/nested.jsonl" \
                LAB_REPORT="$sb/report.txt" LAB_WITHOUT
            LAB_WITHOUT=$(jq -r .without "$sb/run.json")
            LAB_BASE=$(cat "$sb/base")
            # shellcheck source=evals/lab/checks.sh
            . "$LAB/checks.sh"
            # shellcheck disable=SC1091
            . "$scenario/check.sh"
            exit "$lab_fail"
        ) > "$sb/checks.log" 2>&1
        case $? in
            0) verdict=pass ;;
            1) verdict=fail; reason=$(grep -m1 'FAIL' "$sb/checks.log" | sed 's/^ *FAIL *//') ;;
            *) verdict=indeterminate; reason="check.sh itself broke (see checks.log)" ;;
        esac
    fi

    if [ "$verdict" = pass ] && [ -f "$scenario/judge.md" ]; then
        answer=$(judge "$sb" "$scenario")
        judge_cost=$(jq -r '.total_cost_usd // 0' "$sb/judge.json" 2>/dev/null || echo 0)
        case "$answer" in
            PASS) ;;
            FAIL) verdict=fail; reason="the judge answered FAIL (see judge.json)" ;;
            *) verdict=indeterminate; reason="the judge gave no verdict" ;;
        esac
    fi

    nested_cost=$(jq -s 'map(.cost_usd) | add // 0' "$sb/nested.jsonl" 2>/dev/null || echo 0)
    jq --arg scenario "$name" --arg track "$(tr -d '[:space:]' < "$scenario/track")" \
        --arg verdict "$verdict" --arg reason "$reason" \
        --argjson cost "${cost:-0}" --argjson nested "${nested_cost:-0}" --argjson judge "${judge_cost:-0}" \
        --argjson turns "$(jq -s '[.[] | select(.type == "result") | .num_turns // 0] | add // 0' "$sb/transcript.jsonl" 2>/dev/null || echo 0)" \
        '{scenario: $scenario, track: $track, verdict: $verdict, reason: $reason, model: .model,
          without: .without, home: .home, cost_usd: $cost, nested_cost_usd: $nested,
          judge_cost_usd: $judge, seconds: .seconds, turns: $turns}' "$sb/run.json" > "$sb/result.json"
}

if [ -n "$REGRADE" ]; then
    echo "$(date -Iseconds) | REGRADE of $RUN_DIR | judge=$JUDGE_MODEL"
else
    echo "$(date -Iseconds) | model=$MODEL | judge=$JUDGE_MODEL | home=$HOME_MODE${WITHOUT:+ | WITHOUT: $WITHOUT} | claude $("$REAL_CLAUDE" --version 2>/dev/null | head -1)"
    echo "running ${#NAMES[@]} scenario(s), up to $JOBS at a time, into $RUN_DIR"
fi
running=0
for n in "${NAMES[@]}"; do
    if [ -n "$REGRADE" ]; then grade_scenario "$n" & else run_scenario "$n" & fi
    running=$((running+1))
    if [ "$running" -ge "$JOBS" ]; then wait -n; running=$((running-1)); fi
done
wait

fails=0; indet=0; results=()
for n in "${NAMES[@]}"; do
    r="$RUN_DIR/$n/result.json"
    results+=("$r")
    v=$(jq -r .verdict "$r")
    case "$v" in fail) fails=$((fails+1)) ;; indeterminate) indet=$((indet+1)) ;; esac
    printf '  %-13s %-28s $%6.2f  %4dm  %s\n' "$v" "$n" \
        "$(jq -r '.cost_usd + .nested_cost_usd + .judge_cost_usd' "$r")" \
        "$(( $(jq -r .seconds "$r") / 60 ))" "$(jq -r .reason "$r")"
done
echo "-------------------------------------"
printf 'cost: $%.2f | %s failed, %s indeterminate, of %s\n' \
    "$(jq -s 'map(.cost_usd + .nested_cost_usd + .judge_cost_usd) | add' "${results[@]}")" \
    "$fails" "$indet" "${#NAMES[@]}"
[ "$fails" -gt 0 ] && exit 1
[ "$indet" -gt 0 ] && exit 3
exit 0
