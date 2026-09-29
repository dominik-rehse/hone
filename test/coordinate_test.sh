#!/bin/bash
# The coordinate helper and the watch hook, against a fake herdr. The fake
# serves each agent's state from a file, so a test sets a state and runs one
# tick. The field shapes it replays come from
# docs/spikes/2026-09-28-main-tracking-of-subs.md: a run that sits idle at a
# gate unseen, a home-made watcher that dies, and a MAIN that ends its turn
# with no watch. Run: bash test/coordinate_test.sh
set -uo pipefail
unset HERDR_ENV CLAUDE_CODE_SESSION_ID

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
COORD="$PLUGIN_ROOT/scripts/coordinate.sh"
WATCH="$PLUGIN_ROOT/hooks/watch.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

REPO=$(mktemp -d)/mailduct
FAKE="$REPO.fake"
mkdir -p "$REPO" "$FAKE/bin" "$FAKE/agents" "$FAKE/tabs"
cleanup() {
    # A ticker leaves when no session is left.
    rm -rf "$STATE/sessions" 2>/dev/null
    sleep 2
    rm -rf "$(dirname "$REPO")"
}
trap cleanup EXIT
cd "$REPO" || exit 1
git init -q && git symbolic-ref HEAD refs/heads/main
git config user.email t@t.t; git config user.name t
echo seed > README.md && git add -A && git commit -qm seed
STATE="$REPO/.git/hone-coordinate"

cat > "$FAKE/bin/herdr" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE/log"
case "$1 ${2:-}" in
    "--version ") echo "herdr ${FAKE_VERSION:-0.9.2}" ;;
    "agent get")
        f="$FAKE/agents/$3"
        if [ ! -f "$f" ]; then
            echo '{"error":{"code":"agent_not_found","message":"agent target not found"}}' >&2; exit 1
        fi
        read -r st sq tab < "$f"
        printf '{"result":{"agent":{"agent_status":"%s","state_change_seq":%s,"tab_id":"%s"}}}\n' "$st" "$sq" "$tab" ;;
    "tab get") printf '{"result":{"tab":{"label":"%s","tab_id":"%s"}}}\n' "$(cat "$FAKE/tabs/$3" 2>/dev/null)" "$3" ;;
    "notification show") echo '{"result":{"shown":true}}' ;;
esac
STUB
chmod +x "$FAKE/bin/herdr"
export FAKE PATH="$FAKE/bin:$PATH" HONE_COORD_TICK=1
agent() { printf '%s %s %s\n' "$2" "$3" "${4:-w:t1}" > "$FAKE/agents/$1"; }
events() { cat "$STATE/events" 2>/dev/null; }
# One tick of one session, in this shell, with the thresholds at zero.
tick() {
    # shellcheck source=scripts/coordinate.sh disable=SC2034
    ( . "$COORD"; cd "$REPO" || exit 1; COORD_BLOCKED=0; HONE_COORD_QUIET=0
      coord_tick_session "$STATE/sessions/$1" "$STATE" )
}
notified() { grep -c '^notification show' "$FAKE/log" 2>/dev/null || echo 0; }

echo "== coordinate: watch =="
out=$(FAKE_VERSION=0.8.2 bash "$COORD" watch csv-export sub-csv-export 2>&1); rc=$?
[ "$rc" -eq 2 ] && echo "$out" | grep -q 'herdr 0.8.2 is too old' \
    && ok "herdr before 0.9.0 is refused with exit 2" || bad "old herdr should exit 2 (got $rc): $out"
out=$(bash "$COORD" watch csv-export 'Bad Name' 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "an agent name herdr would refuse exits 2" || bad "bad agent name should exit 2 (got $rc)"
printf 'SUB:mail:csv-export\n' > "$FAKE/tabs/w:t1"
agent sub-csv-export working 3
# Hold the ticker lock, so the tests below drive every tick by hand.
mkdir -p "$STATE"
exec 7>"$STATE/ticker.lock"; flock -n 7
out=$(CLAUDE_CODE_SESSION_ID=main-1 bash "$COORD" watch csv-export sub-csv-export 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -qx 'owner=main-1' "$STATE/sessions/sub-csv-export" && grep -qx 'tab=w:t1' "$STATE/sessions/sub-csv-export" \
    && ok "watch registers the session, its owner, and the agent's own tab" || bad "watch should register (rc $rc): $out"

echo "== coordinate: ticks =="
tick sub-csv-export
grep -qx 'status=working' "$STATE/sessions/sub-csv-export" && [ -z "$(events)" ] \
    && ok "a working agent writes no event" || bad "working should write nothing: $(events)"
# The field shape: a run that stops at a gate goes idle, not blocked.
agent sub-csv-export idle 4
tick sub-csv-export
events | grep -qP '\tcsv-export\tquiet\tidle for ' && [ "$(notified)" -eq 1 ] \
    && grep -q 'notification show hone: mailduct/csv-export needs you --body Tab SUB:mail:csv-export: the session went quiet' "$FAKE/log" \
    && ok "an idle run writes a quiet event and notifies with the repository and the tab" \
    || bad "idle should notify once: $(events) / $(cat "$FAKE/log")"
tick sub-csv-export
[ "$(notified)" -eq 1 ] && [ "$(events | wc -l)" -eq 1 ] && ok "the same idle state notifies once" \
    || bad "a second tick on the same state should stay quiet"
agent sub-csv-export working 5; tick sub-csv-export
agent sub-csv-export blocked 6; tick sub-csv-export
events | grep -qP '\tcsv-export\tneeds-you\ta question or an approval prompt$' && [ "$(notified)" -eq 2 ] \
    && ok "a blocked agent writes needs-you and notifies" || bad "blocked should notify: $(events)"
# A land that stopped already told the person: no second notification.
agent sub-csv-export working 7; tick sub-csv-export
( . "$PLUGIN_ROOT/hooks/common.sh"; hone_coord_event "$STATE" csv-export stopped "exit 7, proof gate" )
agent sub-csv-export idle 8; tick sub-csv-export
[ "$(notified)" -eq 2 ] && ! events | tail -1 | grep -q quiet \
    && ok "an idle run after a land that stopped does not notify twice" || bad "land already notified: $(events)"
( . "$PLUGIN_ROOT/hooks/common.sh"; hone_coord_event "$STATE" csv-export landed abc1234 )
tick sub-csv-export
[ ! -f "$STATE/sessions/sub-csv-export" ] && ok "a landed change leaves the watch" || bad "landed should remove the session"
bash "$COORD" watch pdf-export sub-pdf-export w:t2 >/dev/null
rm -f "$FAKE/agents/sub-pdf-export"
tick sub-pdf-export
[ ! -f "$STATE/sessions/sub-pdf-export" ] && events | grep -qP '\tpdf-export\tgone\t' \
    && ok "an agent herdr no longer knows writes gone and leaves the watch" || bad "gone: $(events)"
events | awk -F'\t' '{ if ($1 != NR) bad = 1 } END { exit bad }' \
    && ok "the events are numbered 1, 2, 3, in order" || bad "event numbers: $(events)"

echo "== coordinate: wait =="
out=$(CLAUDE_CODE_SESSION_ID=main-1 timeout 10 bash "$COORD" wait); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'csv-export .*landed .*abc1234' && echo "$out" | grep -q 'pdf-export .*gone' \
    && ok "wait prints the unseen events at once" || bad "wait should print (rc $rc): $out"
out=$(CLAUDE_CODE_SESSION_ID=main-1 timeout 10 bash "$COORD" wait); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'no session is watched, and no event is new' \
    && ok "with nothing seen and nothing watched, wait returns at once" || bad "wait should return (rc $rc): $out"
out=$(timeout 10 bash "$COORD" wait --since 1); rc=$?
[ "$(echo "$out" | wc -l)" -ge 3 ] && ok "wait --since reads from that event on" || bad "wait --since: $out"
agent sub-auth working 1
CLAUDE_CODE_SESSION_ID=main-1 bash "$COORD" watch auth-retry sub-auth >/dev/null
( CLAUDE_CODE_SESSION_ID=main-1 timeout 20 bash "$COORD" wait > "$FAKE/wait.out"; echo "$?" > "$FAKE/wait.rc" ) &
sleep 3
[ -f "$FAKE/wait.rc" ] && bad "wait should block while a session is watched and nothing is new" \
    || ok "wait blocks while a session is watched and nothing is new"
[ -f "$STATE/wait.main-1.pid" ] && kill -0 "$(cat "$STATE/wait.main-1.pid")" 2>/dev/null \
    && ok "a live wait records its pid for the watch hook" || bad "wait should record its pid"
( . "$PLUGIN_ROOT/hooks/common.sh"; hone_coord_event "$STATE" auth-retry stopped "exit 8, authority gate" )
for _ in $(seq 10); do [ -f "$FAKE/wait.rc" ] && break; sleep 1; done
[ "$(cat "$FAKE/wait.rc" 2>/dev/null)" = 0 ] && grep -q 'auth-retry .*stopped .*exit 8' "$FAKE/wait.out" \
    && ok "wait wakes on the next event and prints it" || bad "wait should wake: $(cat "$FAKE/wait.out" 2>/dev/null)"
[ ! -f "$STATE/wait.main-1.pid" ] && ok "the wait removes its pid when it exits" || bad "stale wait pid"

echo "== watch hook =="
stop() { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$REPO" | bash "$WATCH"; }
out=$(stop other-session)
[ -z "$out" ] && ok "a session that watches nothing ends its turn freely" || bad "no watch should not block: $out"
out=$(stop main-1)
echo "$out" | grep -q '"decision":"block"' && echo "$out" | grep -q 'auth-retry' && echo "$out" | grep -q 'coordinate.sh wait' \
    && ok "a watching session with no wait is blocked, and told to run the wait" || bad "should block: $out"
sleep 60 & live=$!
echo "$live" > "$STATE/wait.main-1.pid"
out=$(stop main-1)
[ -z "$out" ] && [ ! -f "$STATE/watch-block.main-1" ] && ok "a live wait lets the turn end and resets the count" \
    || bad "a live wait should pass: $out"
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null
stop main-1 >/dev/null; out2=$(stop main-1); out3=$(stop main-1)
echo "$out2" | grep -q '"decision":"block"' && echo "$out3" | grep -q '"systemMessage"' && ! echo "$out3" | grep -q '"decision"' \
    && ok "the third Stop with no wait lets the turn end and tells the person" || bad "cap: $out3"
touch "$REPO/.hone-off"
[ -z "$(stop main-1)" ] && ok ".hone-off disables the watch hook" || bad ".hone-off should disable it"
rm -f "$REPO/.hone-off"

echo "== coordinate: the ticker =="
# The field shape: a watcher that died. The hook starts the ticker again.
exec 7>&-
[ -f "$STATE/sessions/sub-auth" ] || bad "sub-auth should still be watched"
stop main-1 >/dev/null
sleep 2
flock -n "$STATE/ticker.lock" true && bad "the watch hook should start a ticker" || ok "the watch hook starts a dead ticker again"
out=$(bash "$COORD" list)
echo "$out" | grep -q '^auth-retry .*sub-auth .*working' && ok "list shows each watched session and its state" || bad "list: $out"
rm -f "$FAKE/agents/sub-auth"
for _ in $(seq 10); do [ -f "$STATE/sessions/sub-auth" ] || break; sleep 1; done
events | grep -qP '\tauth-retry\tgone\t' && ok "the background ticker writes events on its own" || bad "ticker: $(events)"
for _ in $(seq 5); do flock -n "$STATE/ticker.lock" true && break; sleep 1; done
flock -n "$STATE/ticker.lock" true && ok "the ticker exits when no session is left" || bad "the ticker should exit"

echo
echo "coordinate_test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
