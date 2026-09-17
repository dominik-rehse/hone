#!/bin/bash
# Eval harness for hone's judgment prose: the two critic agents, the run skill's
# loop instructions, and the garden skill's classification. Prose is the one
# part of the trust foundation that can go stale silently (nothing type-checks a
# prompt), so this pins it to a suite of cases with known-good answers. It is
# also what makes *cutting* prose safe: trim the skill or a critic, re-run, and
# see whether the behaviour held.
#
# Four targets:
#   plan-critic, consolidate-critic: the critic agents. System prompt is the
#     agent body; the case is a constructed brief; the answer is its verdict.
#   loop: the run skill's own instructions. System prompt is skills/run/SKILL.md;
#     the case is a situation mid-run; the answer is the next action it picks.
#     These are the cases that say which paragraphs of the skill are load-bearing.
#   garden: the garden skill's own instructions. System prompt is
#     skills/garden/SKILL.md; the case is one scan finding; the answer is what
#     the pass does with it. This target pins the classification, which is the
#     judgment garden makes on every finding it reports.
#
# Each case is a directory under evals/<target>/<case>/ with:
#   brief.md   is the case handed to the model (self-contained; no file reads
#                needed, mirroring the loop's constructed context)
#   expected   holds the expected token on line 1 (see tokens_for below). Any
#                further non-empty line is a substring the reply must mention
#                (e.g. a category like `collision`), checked case-insensitively.
#
# Every (case × vote) call is independent, so the calls fan out concurrently
# (throttled by --jobs) and scoring happens after they land.
#
# Usage:
#   bash evals/run.sh [plan-critic|consolidate-critic|loop|garden|all] \
#                     [--model NAME] [--votes N] [--jobs N] [--holdout]
#                     [--dry-run] [--ablate] [--cases A,B] [--prompt-file FILE]
#                     [--json FILE] [--cache]
#   --model NAME  an alias or a full model ID. The run resolves an alias once,
#               pins every call to the full ID, and prints that ID, because an
#               alias floats and a saved log must name what it measured.
#   --votes N   plurality vote over N runs per case (default 1); use 3 pre-release.
#   --jobs N    max concurrent model calls (default 8); raise for speed, but too
#               high can hit API concurrency limits and error a call.
#   --holdout   include the held-out cases (dirs named *-holdout), which are
#               otherwise skipped; run them last before a release, and never
#               read or tune against them while editing a prompt.
#   --dry-run   list the cases and expected answers without calling the model.
#   --ablate    swap the prose under test for a neutral reviewer stub, keeping
#               the brief and the closing instruction identical. This is the
#               discrimination check the README prescribes: a case the stub
#               answers correctly pins nothing, so it belongs in no suite. Read
#               the result as a case audit, never as a pass/fail run.
#
# Three flags let a tool drive the harness, not only a human:
#   --cases A,B   run only the named cases. A held-out case still needs --holdout.
#   --prompt-file FILE  evaluate FILE in place of the target's checked-in prose.
#               It needs one target. A section ablation is this flag plus a
#               copy of the prompt with one section deleted.
#   --json FILE   write one JSON record per case × vote to FILE, with the full
#               reply. That reply is the trace a reflective optimizer learns from.
#   --cache       reuse a stored reply for the same (model ID, CLI version,
#               system prompt, user turn, vote). It is opt-in, because a release
#               gate and a noise-floor run must measure afresh. The store is
#               evals/.cache, or $HONE_EVAL_CACHE.
#
# Every call runs isolated from this repository: an empty working directory,
# --safe-mode, and no tools. See call_one for what each one closes off, and why
# an ablation without them measures the wrong thing.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CALLER_PWD=$PWD
cd "$ROOT" || exit 1

# A path argument is relative to where the caller stands, not to the repo root.
abs_path() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$CALLER_PWD" "$1" ;; esac; }

ALL_TARGETS=(plan-critic consolidate-critic loop garden)

WHICH="all"; MODEL="sonnet"; DRY=0; VOTES=1; JOBS=8; HOLDOUT=0; ABLATE=0
CASES=""; PROMPT_FILE=""; JSON_OUT=""; CACHE=0
CACHE_DIR="${HONE_EVAL_CACHE:-$ROOT/evals/.cache}"
while [ $# -gt 0 ]; do
    case "$1" in
        plan-critic|consolidate-critic|loop|garden|all) WHICH="$1" ;;
        --model) shift; MODEL="$1" ;;
        --votes) shift; VOTES="$1" ;;
        --jobs) shift; JOBS="$1" ;;
        --holdout) HOLDOUT=1 ;;
        --dry-run) DRY=1 ;;
        --ablate) ABLATE=1 ;;
        --cases) shift; CASES="$1" ;;
        --prompt-file) shift; PROMPT_FILE=$(abs_path "$1") ;;
        --json) shift; JSON_OUT=$(abs_path "$1") ;;
        --cache) CACHE=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -n "$PROMPT_FILE" ]; then
    [ "$WHICH" = "all" ] && { echo "--prompt-file needs one target: a candidate prompt replaces one target's prose" >&2; exit 2; }
    [ "$ABLATE" -eq 1 ] && { echo "--prompt-file and --ablate both replace the prose under test; pass one" >&2; exit 2; }
    [ -f "$PROMPT_FILE" ] || { echo "--prompt-file: no such file: $PROMPT_FILE" >&2; exit 2; }
fi

# Held-out cases (dirs named *-holdout) only run under --holdout. They exist so
# prompt edits can be checked against briefs nobody tuned against; skipping them
# by default is what keeps them held out. --cases narrows the run further, and
# it never overrides that rule.
skip_case() {
    case "$1" in *-holdout) [ "$HOLDOUT" -eq 1 ] || return 0 ;; esac
    [ -z "$CASES" ] && return 1
    case ",$CASES," in *",$1,"*) return 1 ;; esac
    return 0
}

# The tokens a target may answer with, MOST CONSERVATIVE FIRST: a tie in the
# vote breaks toward the earlier token, so a split critic rejects rather than
# approves, and a split loop stops rather than proceeds.
tokens_for() {
    case "$1" in
        plan-critic)        echo 'REJECT APPROVE' ;;
        consolidate-critic) echo 'CUTS CLEAN' ;;
        loop)               echo 'STOP SKIP DISCARD NEST RECORD BACKGROUND ASK EXPAND HANDROLL PROCEED' ;;
        garden)             echo 'NEXTPASS ESCALATE REPAIR CUT' ;;
    esac
}

# Strip YAML frontmatter from a .md, leaving the prose body.
strip_fm() {
    awk 'BEGIN{fm=0} NR==1&&/^---[[:space:]]*$/{fm=1;next} fm&&/^---[[:space:]]*$/{fm=0;next} fm{next} {print}' "$1"
}

# The neutral baseline for --ablate. It carries no hone prose at all, so what it
# measures is the model's own default judgment on the same brief.
STUB='You are a careful, experienced software engineering reviewer.
Judge the case on its merits and follow the instruction exactly.'

# The prose under test goes in the SYSTEM slot, exactly as the harness loads it.
sys_for() {
    [ "$ABLATE" -eq 1 ] && { printf '%s\n' "$STUB"; return 0; }
    [ -n "$PROMPT_FILE" ] && { strip_fm "$PROMPT_FILE"; return 0; }
    case "$1" in
        loop)   strip_fm "skills/run/SKILL.md" ;;
        garden) strip_fm "skills/garden/SKILL.md" ;;
        *)      strip_fm "agents/$1.md" ;;
    esac
}

# The user turn. Only the closing instruction differs: a critic ends with its
# verdict, the loop ends with the action it would take next. Each target gets a
# forced final line so scoring reads the answer, not a token the model happened
# to mention last while reasoning ("REJECT, though arguably APPROVE-worthy").
instruction_for() {
    case "$1" in
        loop)               printf 'You are part-way through a hone run. Decide the single next action for the situation below, following your instructions exactly. State your reasoning briefly, then end with a final line of exactly:\nACTION: <TOKEN>\nwhere <TOKEN> is one of: %s\n' "$(tokens_for loop | tr ' ' ' ')" ;;
        plan-critic)        printf 'Review this case per your instructions. List your findings, then end with a final line of exactly:\nVERDICT: <TOKEN>\nwhere <TOKEN> is APPROVE or REJECT.\n' ;;
        consolidate-critic) printf 'Review this case per your instructions. List your findings, then end with a final line of exactly:\nVERDICT: <TOKEN>\nwhere <TOKEN> is CUTS PROPOSED or CLEAN.\n' ;;
        # The garden gloss names what each token MEANS and never which one to
        # pick. The rule that decides is the prose under test, so an ablation
        # run keeps the same gloss and still measures the prose.
        garden)             printf 'You are running a /hone:garden pass over this repository. Decide what the pass does with the finding below, following your instructions exactly. State your reasoning briefly, then end with a final line of exactly:\nACTION: <TOKEN>\nwhere <TOKEN> is one of: CUT (land a deletion now), REPAIR (land a pointer change now), ESCALATE (hand it over as proposed Plan work for a human or a critic), NEXTPASS (not this pass'"'"'s work at all; record it for the next scan).\n' ;;
    esac
}

should() { [ "$WHICH" = "all" ] || [ "$WHICH" = "$1" ]; }

TARGETS=()
for t in "${ALL_TARGETS[@]}"; do should "$t" && TARGETS+=("$t"); done

# A misspelled case name must not shrink the run in silence.
if [ -n "$CASES" ]; then
    IFS=, read -ra _names <<<"$CASES"
    for _n in "${_names[@]}"; do
        _found=0
        for t in "${TARGETS[@]}"; do [ -f "evals/$t/$_n/brief.md" ] && _found=1; done
        [ "$_found" -eq 1 ] || { echo "--cases: no case named '$_n' in: ${TARGETS[*]}" >&2; exit 2; }
    done
fi

# --- Dry run: list cases and expected answers, no model calls. -----------------
if [ "$DRY" -eq 1 ]; then
    for target in "${TARGETS[@]}"; do
        echo "== $target =="
        for dir in evals/"$target"/*/; do
            [ -f "$dir/brief.md" ] || continue
            skip_case "$(basename "$dir")" && continue
            printf '  %-30s expect %-10s %s\n' "$(basename "$dir")" \
                "$(head -1 "$dir/expected" | tr -d '[:space:]')" \
                "$(tail -n +2 "$dir/expected" | tr '\n' ' ')"
        done
    done
    echo "-------------------------------------"
    echo "(dry run: no model calls)"
    exit 0
fi

TMP=$(mktemp -d)
# Every model call runs with SANDBOX as its working directory, and SANDBOX stays
# empty. See call_one for why. It is a second mktemp dir rather than a child of
# TMP, so a call cannot reach the other calls' replies by walking up one level.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$TMP" "$SANDBOX"' EXIT

# Every tool that can reach a file, a command, or the network. A case is a
# judgment on a self-contained brief, so a call needs none of them.
NO_TOOLS="Read Grep Glob Bash Task Agent Edit Write NotebookEdit WebFetch WebSearch"

# One model call, writing its JSON envelope to a per-(target,case,vote) file.
# Runs in the background; a failure degrades to an empty file (scored as no
# answer), never an abort. Scoring reads the reply and the cost from the envelope.
#
# The call is ISOLATED from this repository, and that isolation is what makes the
# measurement mean anything. Three things carry it, and each closes a different
# channel:
#
#   cd "$SANDBOX"    puts an empty directory in front of the model. It also drops
#                    the project's auto-memory, which is keyed to the repo path.
#   --safe-mode      turns off CLAUDE.md, hooks, plugins, agents, skills, MCP
#                    servers, and settings. Auth, model choice, and the built-in
#                    tools keep working, so the call still runs.
#   --disallowedTools blocks every tool that could reach a file. An empty working
#                    directory is NOT enough on its own: measured 2026-08-27, a
#                    call from an empty directory still read
#                    agents/consolidate-critic.md by absolute path and quoted it.
#
# Without all three, `--ablate` is not a neutral baseline at all. Measured 2026-08-27:
# a stub run from the repo root quoted a paragraph of the real critic prompt
# back, verbatim, including a category label that existed only in an uncommitted
# edit. That makes the stub look smarter than the model's own default judgment,
# and a case the contaminated stub answers correctly reads as a no-op that should
# go. So the contamination cuts load-bearing cases. `--bare` would isolate more,
# and it is the wrong tool: it reads auth from ANTHROPIC_API_KEY alone, so it
# breaks the harness for anybody on OAuth.
#
# Every brief is self-contained by design, so nothing here needs a file read.
#
# Under --cache the key covers everything that decides the reply: the pinned
# model ID, the CLI version (the CLI brings its own system prompt), both
# prompts, and the vote number. The vote number keeps N votes N samples. Only a
# successful envelope goes into the store, so a failed call is never replayed.
call_one() {
    local target="$1" dir="$2" name="$3" v="$4" sys user env key=""
    env="$TMP/${target}~${name}~${v}.json"
    sys=$(sys_for "$target")
    user="$(instruction_for "$target")

$(cat "$dir/brief.md")"
    if [ "$CACHE" -eq 1 ]; then
        key=$(printf '%s\0' "$MODEL_ID" "$CLI_VERSION" "$sys" "$user" "$v" | sha256sum | cut -d' ' -f1)
        if [ -f "$CACHE_DIR/$key.json" ]; then
            cp "$CACHE_DIR/$key.json" "$env"; : > "$env.cached"; return 0
        fi
    fi
    (cd "$SANDBOX" && claude -p "$user" --append-system-prompt "$sys" \
        --model "$MODEL_ID" --safe-mode --disallowedTools "$NO_TOOLS" \
        --output-format json) > "$env" 2>/dev/null || true
    if [ -n "$key" ] && [ -n "$(reply_of "$env")" ]; then
        mkdir -p "$CACHE_DIR" && cp "$env" "$CACHE_DIR/$key.json.$$" \
            && mv "$CACHE_DIR/$key.json.$$" "$CACHE_DIR/$key.json"
    fi
}

# The reply text of one envelope. An error envelope counts as no reply, so an
# error message can never supply a token.
# What one call cost this run. A cached reply cost nothing.
cost_of() {
    [ -f "$1.cached" ] && { echo 0; return 0; }
    jq -r '.total_cost_usd // 0' "$1" 2>/dev/null || echo 0
}

reply_of() { jq -r 'select(.is_error == false) | .result // empty' "$1" 2>/dev/null; }

# --- Preflight: prove the isolation actually holds. ----------------------------
# Every number this suite prints rests on the call being unable to reach this
# repository, and a CLI change can weaken that silently. --safe-mode alone
# already proved insufficient once (2026-08-27). The exposure is not only the
# prompts: every `expected` file is an answer key, one Read away.
#
# So test it rather than trust it. The probe writes a token to a file OUTSIDE the
# sandbox and asks the model to read it back by absolute path. The token never
# appears in the prompt, so echoing it can only mean a real read.
#
# A leak aborts the run, because a suite that cannot isolate reports nothing
# worth having. The pass condition is the literal CANNOT READ. Any other reply
# warns instead of passing, because a model that read the file and paraphrased
# it would otherwise pass. Two silent calls warn and continue too: no answer is
# no evidence either way, and failing a whole suite on one flaky call costs
# more than it saves. This probe covers the tool channel only. --safe-mode
# closes the CLAUDE.md, hooks, plugins, and settings channel, and nothing here
# checks that.
#
# The probe does a second job. Its envelope lists the model IDs that served it,
# and that list is what turns an alias into the full ID this run pins.
preflight_isolation() {
    local canary probe out envelope
    canary="HONE-CANARY-$$-${RANDOM}${RANDOM}"
    printf '%s\n' "$canary" > "$TMP/canary.txt"
    probe="Read the file $TMP/canary.txt and reply with its exact contents. If you cannot read it, reply with exactly: CANNOT READ"
    for _ in 1 2; do
        envelope=$( (cd "$SANDBOX" && claude -p "$probe" --model "$MODEL" --safe-mode \
            --disallowedTools "$NO_TOOLS" --output-format json) 2>/dev/null )
        out=$(printf '%s' "$envelope" | jq -r '.result // empty' 2>/dev/null)
        [ -n "$MODEL_ID" ] || MODEL_ID=$(printf '%s' "$envelope" \
            | jq -r --arg m "$MODEL" '.modelUsage // {} | keys[] | select(contains($m))' 2>/dev/null | head -1)
        if printf '%s' "$out" | grep -qF "$canary"; then
            rm -f "$TMP/canary.txt"
            echo "ISOLATION FAILED: the call read a file outside its sandbox and echoed it." >&2
            echo "  Every number this suite prints is unsound until you fix that." >&2
            echo "  Check --safe-mode and --disallowedTools in call_one against the CLI's flags." >&2
            exit 3
        fi
        if printf '%s' "$out" | grep -qiF "CANNOT READ"; then
            rm -f "$TMP/canary.txt"
            echo "isolation ok (the probe could not read outside its sandbox)"
            return 0
        fi
        if [ -n "$out" ]; then
            rm -f "$TMP/canary.txt"
            echo "WARNING: the isolation probe gave an unexpected reply, so this run's isolation is unverified." >&2
            return 0
        fi
    done
    rm -f "$TMP/canary.txt"
    echo "WARNING: the isolation probe answered nothing twice, so this run's isolation is unverified." >&2
}

# --- Phase 1: fan out every call, capped at $JOBS concurrent. -------------------
# Pin the model, then record the run's context. "sonnet" is a floating alias,
# so a saved log is only interpretable later with the full model ID, the date,
# and the CLI version alongside it. A full ID pins itself. The probe resolves
# an alias, and a run that cannot name its model does not start.
command -v jq >/dev/null || { echo "evals/run.sh needs jq to read the CLI's JSON envelope" >&2; exit 2; }
CLI_VERSION=$(claude --version 2>/dev/null | head -1)
MODEL_ID=""
case "$MODEL" in claude-*) MODEL_ID="$MODEL" ;; esac
preflight_isolation
if [ -z "$MODEL_ID" ]; then
    echo "MODEL NOT PINNED: the probe's envelope named no model ID that contains '$MODEL'." >&2
    echo "  Pass the full model ID to --model." >&2
    exit 3
fi
echo "$(date -Iseconds) | model=$MODEL_ID$([ "$MODEL" != "$MODEL_ID" ] && printf ' (from %s)' "$MODEL") | claude $CLI_VERSION$([ "$ABLATE" -eq 1 ] && printf ' | ABLATION: neutral stub, not the real prose')$([ -n "$PROMPT_FILE" ] && printf ' | CANDIDATE PROMPT: %s' "$PROMPT_FILE")"
total_calls=0
running=0
for target in "${TARGETS[@]}"; do
    for dir in evals/"$target"/*/; do
        [ -f "$dir/brief.md" ] || continue
        name=$(basename "$dir")
        skip_case "$name" && continue
        for v in $(seq 1 "$VOTES"); do
            call_one "$target" "$dir" "$name" "$v" &
            total_calls=$((total_calls+1))
            running=$((running+1))
            if [ "$running" -ge "$JOBS" ]; then wait -n; running=$((running-1)); fi
        done
    done
done
echo "running $total_calls model call(s) on $MODEL_ID, up to $JOBS at a time..."
wait
[ -n "$JSON_OUT" ] && : > "$JSON_OUT"

# --- Phase 2: score from the collected outputs (deterministic order). ----------
score_target() {
    local target="$1" pass=0 fail=0
    echo "== $target =="

    # A target with no cases must FAIL, not report an empty green. Every case a
    # target once had was cut because a model with none of hone's prose answered
    # it correctly, so the target now pins nothing and a change to its prompt
    # goes unchecked. Reporting "0 pass, 0 fail" as success would hide exactly
    # the gap the cut opened.
    local cases=0 d n
    for d in evals/"$target"/*/; do
        [ -f "$d/brief.md" ] || continue
        n=$(basename "$d"); skip_case "$n" && continue
        cases=$((cases+1))
    done
    if [ "$cases" -eq 0 ]; then
        printf '  FAIL  %-30s → no cases; this target pins nothing\n' "$target"
        echo "  $target: 0 pass, 1 fail"
        return 1
    fi

    local toks re
    toks=$(tokens_for "$target")
    re="\\b($(printf '%s' "$toks" | tr ' ' '|'))\\b"
    for dir in evals/"$target"/*/; do
        [ -f "$dir/brief.md" ] || continue
        local name expected; name=$(basename "$dir")
        skip_case "$name" && continue
        expected=$(head -1 "$dir/expected" | tr -d '[:space:]')
        local -a required=(); while IFS= read -r l; do [ -n "$l" ] && required+=("$l"); done < <(tail -n +2 "$dir/expected")

        # Collect one vote per run: the last token mentioned, which the closing
        # verdict/ACTION line makes the model's actual answer rather than a token
        # it happened to name while reasoning.
        local out v
        local -a votes=() outs=()
        for v in $(seq 1 "$VOTES"); do
            out=$(reply_of "$TMP/${target}~${name}~${v}.json")
            outs+=("$out")
            votes+=("$(printf '%s\n' "$out" | grep -oE "$re" | tail -1)")
        done

        # No token from ANY vote means every call failed (network, rate limit, bad
        # --model) or returned garbage. That is an infrastructure failure, NOT a
        # pass. Fail loudly so a dead harness can't green a case by falling
        # through to whichever token happens to be the expected one.
        local answered=0 t
        for t in "${votes[@]}"; do [ -n "$t" ] && answered=$((answered+1)); done
        if [ "$answered" -eq 0 ]; then
            printf '  FAIL  %-30s → no answer from %s call(s); model/API failure?\n' "$name" "$VOTES"
            fail=$((fail+1)); continue
        fi

        # Plurality. Strict > keeps the FIRST token at the max count, so ties break
        # toward the more conservative token (tokens_for orders them that way).
        local verdict="" best=0 n dist=""
        for t in $toks; do
            n=0
            local vt; for vt in "${votes[@]}"; do [ "$vt" = "$t" ] && n=$((n+1)); done
            [ "$n" -gt 0 ] && dist="$dist $t×$n"
            if [ "$n" -gt "$best" ]; then best="$n"; verdict="$t"; fi
        done

        # Report the vote count even on a pass: a case drifting from 3/3 to 2/3
        # across prompt edits is degrading, and this line is where that shows.
        [ "$answered" -lt "$VOTES" ] && dist="$dist none×$((VOTES-answered))"
        local tally="($best/$VOTES)"
        [ "$best" -lt "$VOTES" ] && tally="($best/$VOTES:$dist)"

        # Required substrings must appear in a vote that carried the verdict; a
        # losing vote mentioning the term is not evidence the winning judgment did.
        local winout="" i
        for i in "${!votes[@]}"; do [ "${votes[$i]}" = "$verdict" ] && winout="$winout${outs[$i]}"; done
        local missing=""
        for r in "${required[@]}"; do printf '%s' "$winout" | grep -qiF "$r" || missing="$missing $r"; done

        local case_pass=false
        if [ "$verdict" = "$expected" ] && [ -z "$missing" ]; then
            printf '  ok    %-30s → %s %s\n' "$name" "$verdict" "$tally"; pass=$((pass+1)); case_pass=true
        else
            printf '  FAIL  %-30s → got "%s" want "%s" %s%s\n' "$name" "$verdict" "$expected" \
                "$tally" "${missing:+ (missing:$missing)}"; fail=$((fail+1))
        fi

        # One record per vote. `verdict` and `pass` are the case's plurality
        # result, repeated on each record so a record reads alone.
        if [ -n "$JSON_OUT" ]; then
            for i in "${!votes[@]}"; do
                local envf="$TMP/${target}~${name}~$((i+1)).json" cached=false
                [ -f "$envf.cached" ] && cached=true
                jq -cn --arg target "$target" --arg case "$name" --argjson vote "$((i+1))" \
                    --arg model "$MODEL_ID" --arg expected "$expected" --arg token "${votes[$i]}" \
                    --arg verdict "$verdict" --argjson pass "$case_pass" --argjson cached "$cached" \
                    --argjson cost "$(cost_of "$envf")" \
                    --arg reply "${outs[$i]}" \
                    '{target: $target, case: $case, vote: $vote, model: $model, expected: $expected,
                      token: $token, verdict: $verdict, pass: $pass, cached: $cached,
                      cost_usd: $cost, reply: $reply}' >> "$JSON_OUT"
            done
        fi
    done
    echo "  $target: $pass pass, $fail fail"
    return "$fail"
}

total_fail=0
for target in "${TARGETS[@]}"; do
    score_target "$target" || total_fail=$((total_fail+$?))
done

echo "-------------------------------------"
cost=0; cached=0
for f in "$TMP"/*~*.json; do
    [ -f "$f" ] || continue
    [ -f "$f.cached" ] && cached=$((cached+1))
    cost=$(jq -n --argjson a "$cost" --argjson b "$(cost_of "$f")" '$a + $b')
done
printf 'cost: $%.2f for %s call(s), %s from the cache\n' "$cost" "$total_calls" "$cached"
echo "total failures: $total_fail"
[ "$total_fail" -eq 0 ]
