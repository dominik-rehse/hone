# The OAuth session token that a sandboxed run borrows, and the wait that
# renews it. Sourced by evals/lab/run.sh and evals/probes/*/run.sh, which set
# $CREDENTIALS and $REAL_CLAUDE first.
#
# A run reads one value, the access token, out of the credentials file and
# hands it to the sandbox. It never copies the file: the file also holds the
# refresh token, and a refresh inside a copy can log the real session out.
#
# A scenario needs the token to outlive it, so a run refuses a token with less
# than $TOKEN_MARGIN left. The CLI renews a token only in the last minutes of
# its life, and until 2026-09-19 the refusal and the renewal shared one
# window: a pass that started between them made one cheap call that renewed
# nothing, and then lost every scenario to the refusal. A pass of nineteen
# lost all nineteen that way. So the fix is to wait. The cheap call goes out
# again every $TOKEN_WAIT_STEP until expiresAt moves, which is the only proof
# that a renewal happened.
#
# A renewal revokes the old token at once, and a scenario holding it dies with
# a 401. So the wait runs before the fan-out, and never while a scenario holds
# a token.

TOKEN_MARGIN="${TOKEN_MARGIN:-1800}"       # a scenario needs this much left
TOKEN_WAIT_STEP="${TOKEN_WAIT_STEP:-120}"  # between two cheap calls
TOKEN_WAIT_MAX="${TOKEN_WAIT_MAX:-2700}"   # give up after this long

# The access token, printed only when it outlives $TOKEN_MARGIN.
session_token() {
    # shellcheck disable=SC2016  # $now and $margin are jq variables
    jq -r --argjson now "$(date +%s)" --argjson margin "$TOKEN_MARGIN" \
        '.claudeAiOauth | select((.expiresAt // 0) / 1000 > $now + $margin) | .accessToken // empty' \
        "$CREDENTIALS" 2>/dev/null
}

# Whole minutes left on the token, floored, and 0 for a file it cannot read.
token_minutes_left() {
    local exp
    exp=$(jq -r '(.claudeAiOauth.expiresAt // 0) / 1000 | floor' "$CREDENTIALS" 2>/dev/null)
    echo $(( ( ${exp:-0} - $(date +%s) ) / 60 ))
}

# One cheap call in the real HOME. The CLI renews on it, when the token is
# close enough to expiry for the CLI to bother.
token_refresh_call() {
    "$REAL_CLAUDE" -p "Reply with exactly: OK" \
        --model claude-haiku-4-5-20251001 --safe-mode >/dev/null 2>&1
}

# Wait until the token covers a whole run. 0 when it does, 1 when it never did.
refresh_session_token() {
    [ -n "$(session_token)" ] && return 0
    local waited=0
    printf 'the session token has %s minute(s) left, and a scenario needs %s. Waiting for the CLI to renew it, up to %s minutes.\n' \
        "$(token_minutes_left)" "$(( TOKEN_MARGIN / 60 ))" "$(( TOKEN_WAIT_MAX / 60 ))"
    while :; do
        token_refresh_call
        if [ -n "$(session_token)" ]; then
            printf 'the session token was renewed, and it has %s minute(s) left.\n' "$(token_minutes_left)"
            return 0
        fi
        [ "$waited" -ge "$TOKEN_WAIT_MAX" ] && break
        sleep "$TOKEN_WAIT_STEP"
        waited=$(( waited + TOKEN_WAIT_STEP ))
    done
    printf 'the session token still has %s minute(s) left after %s minutes of waiting. Log in again, or set CLAUDE_CODE_OAUTH_TOKEN.\n' \
        "$(token_minutes_left)" "$(( TOKEN_WAIT_MAX / 60 ))" >&2
    return 1
}
