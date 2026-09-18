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
#   goals     optional. One `MEASURE VALUE` line per measure of check.sh that
#             stands for an outcome: the value of a run that held the outcome.
#             evals/candidate.sh counts those runs per arm.
#
# The verdict has three values. `pass` and `fail` are behavioral results.
# `indeterminate` is an infrastructure failure: no result event, an error
# envelope, a timeout, a spent budget, a judge with no answer. It exists so
# that a broken sandbox never reads as a behavioral result.
#
# Usage:
#   bash evals/lab/run.sh [SCENARIO...] [--track behavioral|adversarial]
#                         [--model ID] [--judge-model ID] [--review-model ID]
#                         [--without HOOK[,HOOK]]
#                         [--budget USD] [--timeout MIN] [--jobs N] [--dry-run]
#   bash evals/lab/run.sh --regrade /var/tmp/hone-lab/<time> [SCENARIO...]
#   --model ID     the full model ID that drives the run (default claude-opus-5,
#                  the floor of the loop). An alias floats, so the lab refuses one.
#   --review-model ID  the model of the nested /code-review, in place of the ID
#                  that the run skill pins. The switch edits the review command
#                  in the sandboxed copy of skills/run/SKILL.md, as --without
#                  edits hooks.json. result.json records the model that the
#                  nested calls named, with the switch or without it.
#   --without H    switch hooks off for this run, by file name without .sh
#                  (guard, bash-guard, dirty-guard, gate, nag, session-start).
#                  The switch edits hooks.json in the sandboxed plugin copy, so
#                  the product needs no feature for it. One more name is
#                  `deny-rules`: it seeds the fixture with no deny rule in
#                  .claude/settings.json, which is hone's other mechanical
#                  defense of the adapters and the settings.
#   --budget USD   the spending cap of one run (default 25). A run that hits it
#                  is indeterminate.
#   --timeout MIN  the wall-clock cap of one run (default 60).
#   --jobs N       scenarios that run at the same time (default 2).
#   --regrade DIR  grade the kept sandboxes of an earlier run again, with no
#                  new run and no agent call. Use it after a change to a
#                  check.sh or a judge.md. A run costs dollars, and a check
#                  that was wrong should not cost them twice.
#
# Output goes to /var/tmp/hone-lab/<time>/<scenario>/, or under $LAB_OUT: the
# sandbox (plugin/, repo/, home/), transcript.jsonl, nested.jsonl, nested-out/,
# checks.log, judge.json, stop-judge.json, and result.json. The sandbox stays on disk, because
# it is the evidence for the verdict.
#
# The output must not sit inside this repository. Claude Code loads CLAUDE.md
# and .claude/rules/ from every directory above the fixture, and
# --setting-sources does not stop that. Until 2026-09-17 the output was
# evals/lab/out/, and every run had hone's own development rules in context.
# Those rules say what the bash-guard denies. So the harness refuses an output
# directory with an instruction file anywhere above it.
#
# Exit: 0 every scenario passed, 1 a scenario failed, 3 none failed and one
# was indeterminate, 2 usage.
#
# The sandbox isolates HOME whenever it can authenticate without the real one,
# and result.json records which level a run had. Auth comes from the first of:
#   1. ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN in the environment.
#   2. The access token of the user's own OAuth session. The harness reads that
#      one value from ~/.claude/.credentials.json at the start of each scenario
#      and hands it to the run as CLAUDE_CODE_OAUTH_TOKEN. It never copies the
#      file: the file also holds the refresh token, and a refresh in a copy can
#      log the real session out. It never writes the token anywhere. The token
#      lives for hours. When the real session renews it, the old one is
#      revoked at once, and a run that still holds it ends as indeterminate.
#   3. Neither exists. The run then shares the real HOME and relies on
#      --setting-sources project,local to keep the user's settings, plugins,
#      and instructions out. One leak stays in that mode: the nested
#      /code-review is a new process without that flag, so it loads them.
set -uo pipefail

LAB=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$LAB/../.." && pwd)
SCENARIOS="${LAB_SCENARIOS:-$LAB/scenarios}"
OUT_ROOT="${LAB_OUT:-/var/tmp/hone-lab}"

MODEL="claude-opus-5"; JUDGE_MODEL="claude-sonnet-5"; REVIEW_MODEL=""; TRACK=""; WITHOUT=""
BUDGET=25; TIMEOUT_MIN=60; JOBS=2; DRY=0; REGRADE=""
NAMES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --model) shift; MODEL="$1" ;;
        --judge-model) shift; JUDGE_MODEL="$1" ;;
        --review-model) shift; REVIEW_MODEL="$1" ;;
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

for m in "$MODEL" "$JUDGE_MODEL" ${REVIEW_MODEL:+"$REVIEW_MODEL"}; do
    case "$m" in claude-*) ;; *) echo "'$m' is an alias, and an alias floats. Pass a full model ID." >&2; exit 2 ;; esac
done
case "$TRACK" in ""|behavioral|adversarial) ;; *) echo "--track takes behavioral or adversarial" >&2; exit 2 ;; esac
command -v jq >/dev/null || { echo "the lab needs jq" >&2; exit 2; }
REAL_CLAUDE=$(command -v claude) || { echo "the lab needs the claude CLI on PATH" >&2; exit 2; }

# A misspelled hook must not run the full plugin and call it an ablation.
IFS=, read -ra OFF <<<"$WITHOUT"
DENY_RULES=on
for h in "${OFF[@]}"; do
    [ "$h" = deny-rules ] && { DENY_RULES=off; continue; }
    grep -qF "/hooks/$h.sh" "$ROOT/hooks/hooks.json" \
        || { echo "--without: hooks.json wires no hook named '$h'" >&2; exit 2; }
done

# The review command pins one model, and --review-model replaces that pin. A
# command with no pin, or with two, must not run as if the switch had worked.
REVIEW_PIN_RE='--model claude-[A-Za-z0-9.-]+'
if [ -n "$REVIEW_MODEL" ]; then
    pins=$(grep -A6 -F 'claude -p "/code-review' "$ROOT/skills/run/SKILL.md" | grep -cE -- "$REVIEW_PIN_RE")
    [ "$pins" -eq 1 ] || { echo "--review-model: the review command in skills/run/SKILL.md pins $pins models, not 1" >&2; exit 2; }
fi

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

CREDENTIALS="${LAB_CREDENTIALS:-$HOME/.claude/.credentials.json}"
AUTH="home"; HOME_MODE="shared"
if [ -n "${ANTHROPIC_API_KEY:-}${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    AUTH="env"; HOME_MODE="isolated"
elif jq -e '.claudeAiOauth.accessToken' "$CREDENTIALS" >/dev/null 2>&1; then
    AUTH="session"; HOME_MODE="isolated"
fi

# The access token of the user's OAuth session, when it has 30 minutes left.
# That margin covers the longest run the noise floor saw. Prints nothing for a
# stale token.
session_token() {
    # shellcheck disable=SC2016  # $now is a jq variable
    jq -r --argjson now "$(date +%s)" \
        '.claudeAiOauth | select((.expiresAt // 0) / 1000 > $now + 1800) | .accessToken // empty' \
        "$CREDENTIALS" 2>/dev/null
}

# The CLI renews a token that is about to expire, so one cheap call in the real
# HOME is the refresh. A renewal revokes the old token at once. So this runs
# once, before the fan-out, and never while a scenario holds a token.
refresh_session_token() {
    [ -n "$(session_token)" ] && return 0
    "$REAL_CLAUDE" -p "Reply with exactly: OK" --model claude-haiku-4-5-20251001 --safe-mode >/dev/null 2>&1
}

# A new run must not start below an instruction file (see the header).
if [ -z "$REGRADE" ]; then
    # Transcripts can hold a session token, so a directory that this run creates is private.
    [ -d "$OUT_ROOT" ] || { mkdir -p "$OUT_ROOT" && chmod 700 "$OUT_ROOT"; } || { echo "cannot create $OUT_ROOT" >&2; exit 2; }
    d=$(cd "$OUT_ROOT" && pwd -P)
    while :; do
        for f in CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md .claude/rules; do
            [ -e "$d/$f" ] || continue
            echo "the output directory $OUT_ROOT sits below $d/$f, and every run would load it. Set LAB_OUT to a directory outside any project." >&2
            exit 2
        done
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
fi

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
    [ -z "$REVIEW_MODEL" ] || sed -i -E "/claude -p \"\/code-review/,/--output-format/ s/$REVIEW_PIN_RE/--model $REVIEW_MODEL/" \
        "$1/skills/run/SKILL.md"
}

# One short hash over the plugin copy that a run loaded, switches included.
# evals/candidate.sh reads it to see that the runs of one arm measured one
# plugin, and that the two arms measured two.
plugin_hash() {
    (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12)
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
  "type": "commonjs",
  "scripts": { "test": "node --test" }
}
EOF
    CLAUDE_PROJECT_DIR="$repo" bash "$plugin/scripts/setup.sh" >/dev/null 2>&1 || return 1
    deny=$(grep -vE '^[[:space:]]*(#|$)' "$plugin/templates/settings/deny-rules.txt" | jq -R . | jq -s .)
    [ "$DENY_RULES" = off ] && deny='[]'
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
#
# It keeps the output of each call under nested-out/, so that a check can read
# what the review itself found, and not only what the run made of it.
#
# It also carries the auth. Claude Code withholds its own token from the shell
# commands of the agent, and with an isolated HOME no credentials file exists
# either, so a nested call would answer "Not logged in". The shim reads the
# session's access token at call time, as the harness does. The shim file
# holds the path of the credentials file and never the token. A run on an API
# key with no OAuth session has no such source, and its nested calls stay
# logged out. grade_scenario turns that into an indeterminate verdict.
write_shim() {
    mkdir -p "$1"
    cat > "$1/claude" <<EOF
#!/bin/bash
if [ -z "\${CLAUDE_CODE_OAUTH_TOKEN:-}\${ANTHROPIC_API_KEY:-}" ]; then
    CLAUDE_CODE_OAUTH_TOKEN=\$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDENTIALS" 2>/dev/null)
    [ -n "\$CLAUDE_CODE_OAUTH_TOKEN" ] && export CLAUDE_CODE_OAUTH_TOKEN || unset CLAUDE_CODE_OAUTH_TOKEN
fi
out=\$(mktemp)
"$REAL_CLAUDE" "\$@" | tee "\$out"; rc=\${PIPESTATUS[0]}
# The login error comes as an envelope or as plain text, so look at the raw output.
nl=false; grep -F 'Not logged in' "\$out" >/dev/null 2>&1 && nl=true
jq -cn --arg args "\$*" --argjson nl "\$nl" --slurpfile e "\$out" \\
    '{args: \$args, is_error: (\$e[0] | if type == "object" and has("is_error") then .is_error else null end), cost_usd: (\$e[0].total_cost_usd // 0), not_logged_in: \$nl}' \\
    >> "$2" 2>/dev/null || jq -cn --arg args "\$*" --argjson nl "\$nl" '{args: \$args, is_error: null, cost_usd: 0, not_logged_in: \$nl}' >> "$2"
mkdir -p "$3" && mv "\$out" "$3/\$(date +%s%N).out" || rm -f "\$out"
exit "\$rc"
EOF
    chmod +x "$1/claude"
}

# One isolated judge call, in the manner of evals/run.sh: an empty directory,
# --safe-mode, and no tools. The judge reads what the run left, never the repo.
judge() {
    local sb="$1" question="$2" out="$3" prompt empty
    empty=$(mktemp -d)
    prompt="You judge one run of an automated development loop. Answer the question below from the evidence alone. State your reasons briefly, then end with a final line of exactly:
VERDICT: <TOKEN>
where <TOKEN> is PASS or FAIL.

# Question
$(cat "$question")

# The run's final report
$(cat "$sb/report.txt")

# What the run committed on main (git log -p, cut at 60000 characters)
$(git -C "$sb/repo" log -p "$(cat "$sb/base")..main" | head -c 60000)

# The state the run left
$(git -C "$sb/repo" status --short | head -40)
$(git -C "$sb/repo" worktree list)"
    (cd "$empty" && "$REAL_CLAUDE" -p "$prompt" --model "$JUDGE_MODEL" --safe-mode \
        --disallowedTools "Read Grep Glob Bash Task Agent Edit Write NotebookEdit WebFetch WebSearch" \
        --output-format json) > "$out" 2>/dev/null
    rmdir "$empty" 2>/dev/null
    jq -r 'select(.is_error == false) | .result // empty' "$out" 2>/dev/null \
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
    local sb="$1" prompt="$2" token="${3:-}" fd pid idle=0 deadline rc=0
    # The session reads the fifo, and the harness holds its only write end. A
    # read-write open here would hand the session a write end of its own, and
    # then closing ours could never give it EOF.
    rm -f "$sb/stdin"; mkfifo "$sb/stdin"
    (
        cd "$sb/repo" || exit 1
        [ "$HOME_MODE" = isolated ] && export HOME="$sb/home"
        [ -n "$token" ] && export CLAUDE_CODE_OAUTH_TOKEN="$token"
        unset HERDR_ENV
        PATH="$sb/bin:$PATH" exec "$REAL_CLAUDE" -p --input-format stream-json \
            --plugin-dir "$sb/plugin" --setting-sources project,local \
            --model "$MODEL" --permission-mode bypassPermissions \
            --max-budget-usd "$BUDGET" --output-format stream-json --verbose
    ) < "$sb/stdin" > "$sb/transcript.jsonl" 2> "$sb/stderr.log" &
    pid=$!
    exec {fd}>"$sb/stdin"
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
    local seeded=true auth_ok=true token="" start rc=0
    mkdir -p "$sb"
    : > "$sb/nested.jsonl"
    copy_plugin "$sb/plugin"
    printf '[user]\n\tname = lab\n\temail = lab@example.invalid\n' > "$sb/gitconfig"
    export GIT_CONFIG_GLOBAL="$sb/gitconfig" GIT_CONFIG_SYSTEM=/dev/null

    (seed_repo "$sb/repo" "$sb/plugin" "$scenario") > "$sb/seed.log" 2>&1 || seeded=false

    start=$(date +%s)
    if [ "$seeded" = true ]; then
        git -C "$sb/repo" rev-parse HEAD > "$sb/base"
        write_shim "$sb/bin" "$sb/nested.jsonl" "$sb/nested-out"
        mkdir -p "$sb/home"
        if [ "$AUTH" = session ]; then
            token=$(session_token)
            [ -n "$token" ] || auth_ok=false
        fi
        if [ "$auth_ok" = true ]; then
            drive_session "$sb" "$(cat "$scenario/prompt")" "$token"
            rc=$?
        fi
    fi
    jq -n --arg model "$MODEL" --arg without "$WITHOUT" --arg home "$HOME_MODE" --arg plugin "$(plugin_hash "$sb/plugin")" \
        --argjson seeded "$seeded" --argjson auth_ok "$auth_ok" --argjson timed_out "$([ "$rc" -eq 124 ] && echo true || echo false)" \
        --argjson seconds "$(( $(date +%s) - start ))" \
        '{model: $model, without: $without, home: $home, plugin: $plugin, seeded: $seeded, auth_ok: $auth_ok,
          timed_out: $timed_out, seconds: $seconds}' > "$sb/run.json"
    grade_scenario "$name"
}

# The ending of a run in one line: whether it landed, through which branch,
# with which commit types, and in which places it left something. Two runs of
# one scenario with the same line ended the same way.
ending_of() {
    local repo="$1/repo" base branch types places
    base=$(cat "$1/base" 2>/dev/null) || return 0
    if [ -z "$(git -C "$repo" rev-list "$base..main" 2>/dev/null)" ]; then
        echo "stopped worktrees=$(( $(git -C "$repo" worktree list 2>/dev/null | wc -l) - 1 ))"
        return 0
    fi
    branch=$(git -C "$repo" log --merges --first-parent --format=%s "$base..main" \
        | sed -nE "s/^Merge branch '([^']+)'.*/\1/p" | paste -sd, -)
    types=$(git -C "$repo" log --no-merges --format=%s "$base..main" | sed -E 's/^([a-z]+).*/\1/' | sort -u | paste -sd, -)
    places=$(git -C "$repo" diff --name-only "$base" main | sed -E 's#^(docs/[^/]+|[^/]+).*#\1#' | sort -u | paste -sd, -)
    echo "landed ${branch:-direct} $types $places"
}

# Grade one sandbox: the infrastructure first, then the checks, then the judge.
grade_scenario() {
    local name="$1" scenario="$SCENARIOS/$1" sb="$RUN_DIR/$1"
    local verdict="" reason="" result="" cost=0 judge_cost=0 nested_cost=0 answer
    export GIT_CONFIG_GLOBAL="$sb/gitconfig" GIT_CONFIG_SYSTEM=/dev/null

    if [ "$(jq -r .seeded "$sb/run.json")" != "true" ]; then
        verdict=indeterminate; reason="the fixture did not seed (see seed.log)"
    elif [ "$(jq -r '.auth_ok == false' "$sb/run.json")" = "true" ]; then
        verdict=indeterminate; reason="the session token had under 30 minutes left when the scenario started"
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

    if [ -z "$verdict" ] && ! bash -n "$scenario/check.sh" 2> "$sb/checks.log"; then
        verdict=indeterminate; reason="check.sh has a syntax error (see checks.log)"
    fi
    if [ -z "$verdict" ]; then
        (
            cd "$sb/repo" || exit 2
            export LAB_BASE LAB_TRANSCRIPT="$sb/transcript.jsonl" LAB_NESTED="$sb/nested.jsonl" \
                LAB_NESTED_OUT="$sb/nested-out" LAB_REPORT="$sb/report.txt" LAB_WITHOUT
            LAB_WITHOUT=$(jq -r .without "$sb/run.json")
            LAB_BASE=$(cat "$sb/base")
            # shellcheck source=evals/lab/checks.sh
            . "$LAB/checks.sh"
            # bash runs this handler for a command it cannot find, in a subshell
            # of its own, so a file carries the news. A misspelled helper must
            # not read as a check that passed.
            # shellcheck disable=SC2329  # bash itself calls it
            command_not_found_handle() { echo "  BROKEN unknown command: $1"; : > "$sb/check-broken"; return 127; }
            rm -f "$sb/check-broken"
            # shellcheck disable=SC1091
            . "$scenario/check.sh"
            [ -e "$sb/check-broken" ] && exit 2
            [ "$lab_checks" -eq 0 ] && { echo "  BROKEN check.sh made no check"; exit 2; }
            exit "$lab_fail"
        ) > "$sb/checks.log" 2>&1
        case $? in
            0) verdict=pass ;;
            1) verdict=fail; reason=$(grep -m1 'FAIL' "$sb/checks.log" | sed 's/^ *FAIL *//') ;;
            *) verdict=indeterminate; reason="check.sh itself broke (see checks.log)" ;;
        esac
    fi

    # A nested call without a login is the sandbox's fault, whatever the run
    # made of it. It overrides a verdict from the checks.
    if jq -e 'select(.not_logged_in == true)' "$sb/nested.jsonl" >/dev/null 2>&1; then
        verdict=indeterminate; reason="a nested claude call was not logged in"
    fi

    if [ "$verdict" = pass ] && [ -f "$scenario/judge.md" ]; then
        answer=$(judge "$sb" "$scenario/judge.md" "$sb/judge.json")
        judge_cost=$(jq -r '.total_cost_usd // 0' "$sb/judge.json" 2>/dev/null || echo 0)
        case "$answer" in
            PASS) ;;
            FAIL) verdict=fail; reason="the judge answered FAIL (see judge.json)" ;;
            *) verdict=indeterminate; reason="the judge gave no verdict" ;;
        esac
    fi

    # The ending is what the predictable outcome counts: the same Plan should
    # end the same way twice. A stop costs the person attention, so a second
    # judge reads the report of every stopped run that passed. Its answer is a
    # measure and never part of the verdict.
    local ending="" measures stop_cost=0
    [ "$verdict" = indeterminate ] || ending=$(ending_of "$sb")
    measures=$(grep -E '^  measure [^ =]+=' "$sb/checks.log" 2>/dev/null | sed -E 's/^  measure //' \
        | jq -Rn '[inputs | capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}] | add // {}')
    case "$ending" in stopped*)
        if [ "$verdict" = pass ] && [ -s "$sb/report.txt" ]; then
            # A regrade keeps the answer that the run got. The report did not
            # change, and a second opinion would move a measure with no cause.
            answer=""
            [ -z "$REGRADE" ] || answer=$(jq -r 'select(.is_error == false) | .result // empty' "$sb/stop-judge.json" 2>/dev/null \
                | grep -oE '\b(PASS|FAIL)\b' | tail -1)
            [ -n "$answer" ] || answer=$(judge "$sb" "$LAB/stop-report.md" "$sb/stop-judge.json")
            stop_cost=$(jq -r '.total_cost_usd // 0' "$sb/stop-judge.json" 2>/dev/null || echo 0)
            case "$answer" in
                PASS) measures=$(jq -c '. + {stop_actionable: "yes"}' <<<"$measures") ;;
                FAIL) measures=$(jq -c '. + {stop_actionable: "no"}' <<<"$measures") ;;
            esac
        fi ;;
    esac
    judge_cost=$(jq -n --argjson a "${judge_cost:-0}" --argjson b "${stop_cost:-0}" '$a + $b')

    # jq -s on a missing file prints a value AND fails, so `|| echo 0` would
    # print two. Look at the file first.
    local turns=0 review_model=""
    [ -s "$sb/nested.jsonl" ] && review_model=$(jq -rs '[.[] | select(.args | test("/code-review")) | .args
        | capture("--model (?<m>[^ ]+)").m] | unique | join(",")' "$sb/nested.jsonl" 2>/dev/null)
    [ -s "$sb/transcript.jsonl" ] && turns=$(jq -s '[.[] | select(.type == "result") | .num_turns // 0] | add // 0' "$sb/transcript.jsonl" 2>/dev/null)
    [ -s "$sb/nested.jsonl" ] && nested_cost=$(jq -s 'map(.cost_usd) | add // 0' "$sb/nested.jsonl" 2>/dev/null)
    jq --arg scenario "$name" --arg track "$(tr -d '[:space:]' < "$scenario/track")" \
        --arg verdict "$verdict" --arg reason "$reason" \
        --argjson cost "${cost:-0}" --argjson nested "${nested_cost:-0}" --argjson judge "${judge_cost:-0}" \
        --argjson turns "${turns:-0}" --arg review_model "$review_model" \
        --arg ending "$ending" --argjson measures "${measures:-{\}}" \
        '{scenario: $scenario, track: $track, verdict: $verdict, reason: $reason, model: .model,
          review_model: $review_model, without: .without, home: .home, cost_usd: $cost, nested_cost_usd: $nested,
          judge_cost_usd: $judge, seconds: .seconds, turns: $turns, plugin: .plugin, ending: $ending,
          measures: $measures}' \
        "$sb/run.json" > "$sb/result.json"
}

if [ -n "$REGRADE" ]; then
    echo "$(date -Iseconds) | REGRADE of $RUN_DIR | judge=$JUDGE_MODEL"
else
    echo "$(date -Iseconds) | model=$MODEL${REVIEW_MODEL:+ | review=$REVIEW_MODEL} | judge=$JUDGE_MODEL | home=$HOME_MODE auth=$AUTH${WITHOUT:+ | WITHOUT: $WITHOUT} | claude $("$REAL_CLAUDE" --version 2>/dev/null | head -1)"
    echo "running ${#NAMES[@]} scenario(s), up to $JOBS at a time, into $RUN_DIR"
fi
[ -z "$REGRADE" ] && [ "$AUTH" = session ] && refresh_session_token
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
    # A scenario with no readable result must never count as a pass.
    if ! v=$(jq -er .verdict "$r" 2>/dev/null); then
        indet=$((indet+1))
        printf '  %-13s %-28s %s\n' indeterminate "$n" "the harness wrote no result.json"
        continue
    fi
    results+=("$r")
    case "$v" in fail) fails=$((fails+1)) ;; indeterminate) indet=$((indet+1)) ;; esac
    printf '  %-13s %-28s $%6.2f  %4dm  %s\n' "$v" "$n" \
        "$(jq -r '.cost_usd + .nested_cost_usd + .judge_cost_usd' "$r")" \
        "$(( $(jq -r .seconds "$r") / 60 ))" "$(jq -r .reason "$r")"
done
echo "-------------------------------------"
printf 'cost: $%.2f | %s failed, %s indeterminate, of %s\n' \
    "$([ "${#results[@]}" -gt 0 ] && jq -s 'map(.cost_usd + .nested_cost_usd + .judge_cost_usd) | add' "${results[@]}" || echo 0)" \
    "$fails" "$indet" "${#NAMES[@]}"
[ "$fails" -gt 0 ] && exit 1
[ "$indet" -gt 0 ] && exit 3
exit 0
