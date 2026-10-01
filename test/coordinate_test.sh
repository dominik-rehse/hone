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
mkdir -p "$REPO" "$FAKE/bin" "$FAKE/agents" "$FAKE/tabs" "$FAKE/panes"
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
    "tab get") printf '{"result":{"tab":{"agent_status":"idle","label":"%s","number":1,"tab_id":"%s"}}}\n' "$(cat "$FAKE/tabs/$3" 2>/dev/null)" "$3" ;;
    "tab list")
        # herdr 0.9.2's order: label before tab_id, other fields between.
        printf '{"id":"cli:tab:list","result":{"tabs":['
        sep=""
        for t in "$FAKE"/tabs/*; do
            printf '%s{"agent_status":"idle","focused":false,"label":"%s","number":1,"pane_count":1,"tab_id":"%s","workspace_id":"w"}' "$sep" "$(cat "$t")" "$(basename "$t")"
            sep=","
        done
        printf '],"type":"tab_list"}}\n' ;;
    "tab rename") printf '%s\n' "$4" > "$FAKE/tabs/$3" ;;
    "tab create")
        n=$(( $(cat "$FAKE/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE/n"
        label=$(printf '%s\n' "$@" | grep -A1 -x -- --label | tail -1)
        printf '%s\n' "$label" > "$FAKE/tabs/w:t$n"; printf 'w:t%s\n' "$n" > "$FAKE/panes/w:p$n"
        printf '{"result":{"tab":{"tab_id":"w:t%s","label":"%s"},"root_pane":{"pane_id":"w:p%s"}}}\n' "$n" "$label" "$n" ;;
    "agent start")
        pane=$(printf '%s\n' "$@" | grep -A1 -x -- --pane | tail -1)
        printf 'idle 1 %s\n' "$(cat "$FAKE/panes/$pane")" > "$FAKE/agents/$3" ;;
    "agent prompt") read -r _ _ tab < "$FAKE/agents/$3"; printf 'working 2 %s\n' "$tab" > "$FAKE/agents/$3" ;;
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

echo "== coordinate: admit =="
exec 7>"$STATE/ticker.lock"; flock -n 7
mkdir -p .plans
printf '# csv-export\n\nFiles: src/export/csv.ts\n' > .plans/csv-export.md
printf '# pdf-export\n\nFiles: src/export/pdf.ts\n' > .plans/pdf-export.md
git add -A && git commit -qm "plans"
out=$(bash "$COORD" admit pdf-export); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'disjoint from the 0 change' && echo "$out" | grep -q 'src/export/pdf.ts' \
    && ok "with nothing in flight, admit prints the candidate's Plan and exits 0" || bad "admit, nothing in flight (rc $rc): $out"
git worktree add -q -b hone/csv-export .worktrees/csv-export
out=$(bash "$COORD" admit csv-export); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q 'csv-export is in flight already (this clone)' \
    && ok "a change in flight already is refused with exit 4" || bad "in flight (rc $rc): $out"
out=$(bash "$COORD" admit pdf-export); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q '^=== csv-export (this clone)$' && echo "$out" | grep -q 'src/export/csv.ts' \
    && ok "admit prints each change in flight with its owner and its Plan" || bad "admit compare (rc $rc): $out"
out=$(bash "$COORD" admit garden); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q 'garden waits' && echo "$out" | grep -q 'csv-export (this clone)' \
    && ok "garden waits while any other change is in flight" || bad "garden (rc $rc): $out"
printf 'change=garden\nagent=sub-garden\nowner=main-1\n' > "$STATE/sessions/sub-garden"
out=$(bash "$COORD" admit pdf-export); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q 'a garden pass is in flight' \
    && ok "a run waits while garden is in flight" || bad "run next to garden (rc $rc): $out"
rm -f "$STATE/sessions/sub-garden"

echo "== coordinate: admit in shared mode =="
# Another developer claimed rate-limit and committed its Plan on the remote.
git init -q --bare "$REPO.remote"
git remote add origin "$REPO.remote"
printf 'origin\n' > .hone-shared && git add .hone-shared && git commit -qm shared && git push -q origin main
git clone -q "$REPO.remote" "$REPO.anna"
( cd "$REPO.anna" && git config user.email a@a && git config user.name anna
  mkdir -p .plans && printf '# rate-limit\n\nFiles: src/auth/session.ts\n' > .plans/rate-limit.md
  git add -A && git commit -qm "plan rate-limit" && git push -q origin main
  sha=$(git commit-tree "$(git hash-object -t tree /dev/null)" -m "hone claim: rate-limit by anna <a@a> on laptop at 2026-09-29T10:00:00+02:00")
  git push -q origin "$sha:refs/hone/claim/rate-limit" )
git fetch -q origin
out=$(bash "$COORD" admit pdf-export); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q '^=== rate-limit (anna on laptop)$' && echo "$out" | grep -q 'src/auth/session.ts' \
    && ok "admit reads another developer's claim and the Plan from the remote" || bad "shared admit (rc $rc): $out"
( cd "$REPO.anna" && printf '# Plan: tax-export\nOwner: anna\n\nFiles: src/tax/export.ts\n' > .plans/tax-export.md
  git add -A && git commit -qm "plan tax-export" && git push -q origin main )
git fetch -q origin
out=$(bash "$COORD" admit tax-export); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q 'names anna as its owner' \
    && ok "a Plan whose Owner line names a colleague is not admitted" || bad "owned Plan (rc $rc): $out"
out=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=anna bash "$COORD" admit tax-export); rc=$?
[ "$rc" -eq 0 ] && ok "the owner's own coordinator admits the Plan" || bad "owner admits (rc $rc): $out"
out=$(bash "$COORD" admit rate-limit); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q 'anna on laptop' \
    && ok "a change another developer claimed is refused with its owner" || bad "claimed by anna (rc $rc): $out"
git remote remove origin; git rm -q .hone-shared && git commit -qm "not shared"
git update-ref -d refs/hone/remote-claim/rate-limit

echo "== coordinate: start =="
: > "$FAKE/log"
out=$(bash "$COORD" start run pdf-export 2>&1); rc=$?
[ "$rc" -eq 2 ] && echo "$out" | grep -q 'does not run inside herdr' \
    && ok "start outside herdr exits 2" || bad "start outside herdr (rc $rc): $out"
printf 'claude\n' > "$FAKE/tabs/w:t0"
export HERDR_ENV=1 HERDR_WORKSPACE_ID=w HERDR_TAB_ID=w:t0
out=$(CLAUDE_CODE_SESSION_ID=main-1 bash "$COORD" start run pdf-export 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'started run pdf-export in tab run:pdf-export (agent run-pdf-export, model opus)' \
    && ok "start run opens the tab, starts the agent, and says so" || bad "start run (rc $rc): $out"
grep -q -- "^tab create --workspace w --cwd $REPO --label run:pdf-export --no-focus$" "$FAKE/log" \
    && grep -q -- '^agent start run-pdf-export --kind claude --pane w:p[0-9]* -- --permission-mode auto --model opus$' "$FAKE/log" \
    && grep -q -- '^agent prompt run-pdf-export /hone:run pdf-export$' "$FAKE/log" \
    && [ "$(grep -c '^agent prompt' "$FAKE/log")" -eq 1 ] \
    && ok "the session opens in the background, in auto mode, on opus, with one prompt" || bad "start calls: $(cat "$FAKE/log")"
grep -qx 'owner=main-1' "$STATE/sessions/run-pdf-export" && grep -qx 'change=pdf-export' "$STATE/sessions/run-pdf-export" \
    && ok "start registers the watch for the calling session" || bad "start should watch"
: > "$FAKE/log"
out=$(bash "$COORD" start run pdf-export 2>&1); rc=$?
[ "$rc" -eq 4 ] && ! grep -q '^tab create' "$FAKE/log" \
    && ok "start refuses a change in flight before it opens a tab" || bad "start in flight (rc $rc): $out"
agent run-auth-retry idle 9
out=$(bash "$COORD" start run auth/retry --model sonnet 2>&1); rc=$?
echo "$out" | grep -q 'agent run-auth-retry-2, model sonnet' \
    && grep -q -- '--label run:auth/retry' "$FAKE/log" \
    && ok "an agent name follows herdr's form, and a collision gets -2" || bad "agent name (rc $rc): $out"
: > "$FAKE/log"
out=$(bash "$COORD" start plan "An invoice export, for Q3" 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -q -- '--label plan:an-invoice-export-for-q3 --no-focus$' "$FAKE/log" \
    && grep -q -- '^agent prompt plan-an-invoice-export-for-q3 /hone:plan An invoice export, for Q3$' "$FAKE/log" \
    && grep -qx 'change=plan:an-invoice-export-for-q3' "$STATE/sessions/plan-an-invoice-export-for-q3" \
    && ok "start plan names the tab by the idea, opens it behind, prompts /hone:plan, and watches it" || bad "start plan (rc $rc): $out / $(cat "$FAKE/log")"
ptab=$(sed -n 's/^tab=//p' "$STATE/sessions/plan-an-invoice-export-for-q3")
bash "$COORD" start plan "an invoice export for Q3" >/dev/null 2>&1
grep -qx 'change=plan:an-invoice-export-for-q3-2' "$STATE/sessions/plan-an-invoice-export-for-q3-2" \
    && grep -q -- '--label plan:an-invoice-export-for-q3-2 --no-focus$' "$FAKE/log" \
    && ok "a second plan of the same idea gets a watch and a label of its own" || bad "plan collision: $(ls "$STATE/sessions")"
out=$(bash "$COORD" admit other-change 2>&1)
! echo "$out" | grep -q 'plan:' && ok "a plan session is not a change in flight" || bad "admit lists the plan: $out"
out=$(HERDR_TAB_ID=$ptab bash "$COORD" planned invoice-export 2>&1); rc=$?
[ "$rc" -eq 2 ] && echo "$out" | grep -q 'not committed' && ! events | grep -qP '\tplanned\t' \
    && ok "planned refuses a Plan that is not committed" || bad "planned uncommitted (rc $rc): $out"
mkdir -p .plans && echo '# Plan' > .plans/invoice-export.md && git add .plans && git commit -qm 'chore(plan): invoice-export'
# The field shape of 2026-10-01: a coordinator on an older hone registered no
# watch for its plan tabs, and planned returned 0 in silence 30 times.
out=$(HERDR_TAB_ID=w:t99 bash "$COORD" planned invoice-export 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'no watch names this tab' \
    && events | grep -qP '\tplan:invoice-export\tplanned\tinvoice-export$' \
    && ok "planned in a tab no watch names says so on stderr and still writes the event" || bad "planned elsewhere (rc $rc): $out / $(events)"
out=$(HERDR_TAB_ID=$ptab bash "$COORD" planned invoice-export 2>&1); rc=$?
[ "$rc" -eq 0 ] && events | grep -qP '\tplan:an-invoice-export-for-q3\tplanned\tinvoice-export$' \
    && grep -qx "tab rename $ptab plan:invoice-export" "$FAKE/log" \
    && ok "planned writes a planned event for the tab's watch and relabels the tab by the slug" || bad "planned (rc $rc): $out / $(events)"
agent plan-an-invoice-export-for-q3 working 3 "$ptab"; tick plan-an-invoice-export-for-q3
[ -f "$STATE/sessions/plan-an-invoice-export-for-q3" ] && ! grep -q "^tab close $ptab" "$FAKE/log" \
    && ok "a planned session keeps its tab while its turn runs" || bad "planned closed a working tab"
agent plan-an-invoice-export-for-q3 idle 4 "$ptab"; tick plan-an-invoice-export-for-q3
[ ! -f "$STATE/sessions/plan-an-invoice-export-for-q3" ] && grep -qx "tab close $ptab" "$FAKE/log" \
    && [ -f "$STATE/sessions/plan-an-invoice-export-for-q3-2" ] \
    && ok "a planned session that goes idle closes its tab and leaves the watch" || bad "planned idle: $(cat "$FAKE/log")"
rm -f "$STATE/sessions/plan-an-invoice-export-for-q3-2"
out=$(bash "$COORD" start plan auth/retry 2>&1)
grep -q -- '--label plan:auth/retry --no-focus$' "$FAKE/log" && grep -qx 'change=plan:auth/retry' "$STATE/sessions/plan-auth-retry" \
    && ok "a nested slug keeps its slash in the plan label" || bad "nested plan label: $out"
rm -f "$STATE/sessions/plan-auth-retry"
git rm -q .plans/invoice-export.md && git commit -qm 'drop plan' && mkdir -p .plans
: > "$FAKE/log"
out=$(bash "$COORD" start garden 2>&1); rc=$?
[ "$rc" -eq 4 ] && ! grep -q '^tab create' "$FAKE/log" \
    && ok "start garden waits while runs are in flight" || bad "start garden (rc $rc): $out"
: > "$FAKE/log"
out=$(bash "$COORD" start consolidate 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -q -- '^agent prompt hone-consolidate Run the global consolidate pass' "$FAKE/log" \
    && [ -f "$STATE/sessions/hone-consolidate" ] \
    && ok "start consolidate prompts the global consolidate pass and watches it" || bad "start consolidate (rc $rc): $out"

echo "== coordinate: open and board =="
out=$(bash "$COORD" open 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$FAKE/tabs/w:t0")" = hone ] && echo "$out" | grep -q 'this tab is hone, the coordinator of mailduct' \
    && ok "open labels this tab hone and prints the board" || bad "open (rc $rc): $out"
printf 'hone\n' > "$FAKE/tabs/w:t99"; printf 'claude\n' > "$FAKE/tabs/w:t0"
out=$(bash "$COORD" open 2>&1)
[ "$(cat "$FAKE/tabs/w:t0")" = hone-2 ] && ok "a second coordinator in the workspace becomes hone-2" || bad "hone-2: $(cat "$FAKE/tabs/w:t0")"
rm -f "$FAKE/tabs/w:t99"
printf '# tax-report\n\nFiles: src/tax/report.ts\n' > .plans/tax-report.md
mkdir -p .plans/tax-report && printf 'a reference\n' > .plans/tax-report/sample.md
agent run-pdf-export blocked 12
( . "$COORD"; cd "$REPO" || exit 1; COORD_BLOCKED=0; coord_tick_session "$STATE/sessions/run-pdf-export" "$STATE" )
( . "$PLUGIN_ROOT/hooks/common.sh"; hone_coord_event "$STATE" old-change landed 1a2b3c4 )
out=$(bash "$COORD" board)
first=$(echo "$out" | sed -n 2p)
echo "$out" | head -1 | grep -q '^mailduct · 2 running · 1 need you · 1 ready$' \
    && echo "$first" | grep -q '^pdf-export .*NEEDS YOU: a question or an approval prompt, tab run:pdf-export' \
    && echo "$out" | grep -q '^csv-export .*in flight .*this clone' \
    && echo "$out" | grep -q '^tax-report .*Plan ready' && ! echo "$out" | grep -q 'tax-report/sample' \
    && echo "$out" | grep -q '^old-change .*landed 1a2b3c4' \
    && ok "board puts what needs you first, then running, in flight, ready, and landed" || bad "board: $out"
out=$(bash "$COORD" board src/tax)
[ "$(echo "$out" | sed -n '2,$p' | wc -l)" -eq 1 ] && echo "$out" | grep -q '^tax-report' \
    && echo "$out" | head -1 | grep -q '^mailduct · 0 running · 0 need you · 1 ready$' \
    && ok "board <path> keeps the changes whose Plan names the path, and counts only those" || bad "board filter: $out"
unset HERDR_ENV HERDR_WORKSPACE_ID HERDR_TAB_ID
rm -f "$STATE"/sessions/*
exec 7>&-

echo "== coordinate: garden and consolidate end when they go quiet =="
exec 7>"$STATE/ticker.lock"; flock -n 7
agent hone-garden idle 3
bash "$COORD" watch garden hone-garden w:t1 >/dev/null
git worktree add -q -b hone/garden/cut-x .worktrees/garden/cut-x
tick hone-garden
[ -f "$STATE/sessions/hone-garden" ] && ! events | grep -qP '\tgarden\tfinished\t' \
    && ok "a quiet garden session whose cut holds a worktree stays watched" || bad "garden with a worktree: $(events | tail -2)"
git worktree remove .worktrees/garden/cut-x && git branch -q -D hone/garden/cut-x
( . "$PLUGIN_ROOT/hooks/common.sh"; hone_coord_event "$STATE" garden/cut-x landed 9f8e7d6 )
agent hone-garden working 4; tick hone-garden
agent hone-garden idle 5; tick hone-garden
[ ! -f "$STATE/sessions/hone-garden" ] && events | grep -qP '\tgarden\tfinished\t' \
    && ok "a quiet garden session with no garden worktree left writes finished and leaves the watch" || bad "garden finished: $(events | tail -2)"
out=$(bash "$COORD" admit tax-report); rc=$?
[ "$rc" -eq 0 ] && ok "after garden finished, admit lets a run start again" || bad "admit after garden (rc $rc): $out"
agent hone-consolidate idle 3
bash "$COORD" watch consolidate hone-consolidate w:t1 >/dev/null
tick hone-consolidate
[ ! -f "$STATE/sessions/hone-consolidate" ] && events | grep -qP '\tconsolidate\tfinished\t' \
    && ok "a quiet consolidate session writes finished and leaves the watch" || bad "consolidate finished: $(events | tail -2)"

echo "== coordinate: a land that stopped needs the person at once =="
agent run-billing working 1
bash "$COORD" watch billing run-billing w:t1 >/dev/null
( . "$COORD"; cd "$REPO" || exit 1; coord_tick_session "$STATE/sessions/run-billing" "$STATE" )
( . "$PLUGIN_ROOT/hooks/common.sh"; hone_coord_event "$STATE" billing stopped "exit 8, authority gate" )
out=$(bash "$COORD" board billing)
echo "$out" | head -1 | grep -q '· 0 running · 1 need you ·' && echo "$out" | grep -q '^billing .*NEEDS YOU: land stopped, exit 8, authority gate' \
    && ok "the board shows a stopped land as a need before the quiet threshold" || bad "stopped on board: $out"
rm -f "$STATE"/sessions/*
exec 7>&-

echo "== field shapes 2026-10-01 (coordinate) =="
exec 7>"$STATE/ticker.lock"; flock -n 7
ver=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" | head -1)
updated() { events | grep -cP '\thone\tupdated\t'; }
# A1: the coordinator ran 0.70.1 all batch while its sessions ran 0.71.1.
agent run-mail working 1
CLAUDE_CODE_SESSION_ID=main-7 bash "$COORD" watch mail run-mail w:t1 >/dev/null
grep -qx "version=$ver" "$STATE/sessions/run-mail" && ok "a watch record carries the hone version of the watch" \
    || bad "watch version: $(cat "$STATE/sessions/run-mail")"
tick run-mail
grep -qx "version=$ver" "$STATE/sessions/run-mail" && ok "a tick keeps the version of the watch" || bad "tick dropped the version"
( . "$PLUGIN_ROOT/hooks/common.sh"; hone_coord_event "$STATE" mail stopped "exit 7, proof gate" )
[ "$(updated)" -eq 0 ] && ok "an event of the coordinator's own version warns of nothing" || bad "same version warned: $(events | tail -2)"
sed -i 's/^version=.*/version=0.70.1/' "$STATE/sessions/run-mail"
n=$(events | wc -l)
( . "$PLUGIN_ROOT/hooks/common.sh"; hone_coord_event "$STATE" mail landed abc1234; hone_coord_event "$STATE" mail gone x )
[ "$(updated)" -eq 1 ] && events | grep -P '\thone\tupdated\t' | grep -q "hone $ver wrote .*runs 0.70.1.*Restart the coordinator session" \
    && ok "a newer hone that writes to an older coordinator's events warns once" || bad "skew warning: $(events | tail -4)"
# A fresh session has a new id and owns no watch. A resume keeps the id.
events | grep -P '\thone\tupdated\t' | grep -q 'claude --resume main-7' \
    && ok "the warning names the resume that keeps the coordinator's watches" || bad "resume hint: $(events | tail -2)"
out=$(timeout 10 bash "$COORD" wait --since "$n")
echo "$out" | grep -q 'hone .*updated .*Restart the coordinator session' && ok "the coordinator's wait prints the warning" \
    || bad "wait should print the warning: $out"
# A record from before the version field counts as older.
sed -i '/^version=/d' "$STATE/sessions/run-mail"; rm -f "$STATE"/updated.*
( . "$PLUGIN_ROOT/hooks/common.sh"; hone_coord_event "$STATE" mail landed abc1234 )
[ "$(updated)" -eq 2 ] && events | tail -2 | grep -q 'runs a hone from before' \
    && ok "a watch record with no version counts as an older coordinator" || bad "no version: $(events | tail -2)"
rm -f "$STATE"/sessions/*
out=$(bash "$COORD" planned no-such-plan 2>&1); rc=$?
[ "$rc" -eq 2 ] && echo "$out" | grep -q 'not committed' && ok "planned with no watch still refuses an uncommitted Plan" \
    || bad "planned uncommitted, no watch (rc $rc): $out"

# A5: the landed event named the caller's HEAD, not the merge land made.
git worktree add -q -b hone/mail .worktrees/mail
( cd .worktrees/mail && echo m > mail.txt && git add -A && git commit -qm mail )
git worktree add -q -b side .worktrees/side main
( cd .worktrees/side && echo s > side.txt && git add -A && git commit -qm side
  # shellcheck source=scripts/worktree.sh
  . "$PLUGIN_ROOT/scripts/worktree.sh"
  # The stub records its merge as cmd_land does. Then another land moves
  # the primary branch before progress_step reads anything.
  cmd_land() { git -C "$REPO" merge -q --no-ff hone/mail -m "Merge branch 'hone/mail'"
               LAND_MERGED_SHA=$(git -C "$REPO" rev-parse --short HEAD)
               git -C "$REPO" commit -q --allow-empty -m "Merge branch 'hone/other'"; }
  progress_step land mail >/dev/null 2>&1 )
merged=$(git -C "$REPO" rev-parse --short HEAD~1)
events | tail -1 | grep -qP "\tmail\tlanded\t$merged$" && [ "$merged" != "$(git -C .worktrees/side rev-parse --short HEAD)" ] \
    && ok "the landed event names the merge land made, not the caller's HEAD or a later land's merge" || bad "landed sha: $(events | tail -1) vs $merged"
git worktree remove --force .worktrees/side; git worktree remove --force .worktrees/mail

# A10: two runs started before the change their Plan named as first.
printf '# Plan: base-a\n\nFiles: src/a.ts\n' > .plans/base-a.md
printf '# Plan: base-b\n\nFiles: src/b.ts\n' > .plans/base-b.md
printf '# Plan: needs-ab\n\n- Order: Start it only after `base-a` and `base-b` have landed.\n' > .plans/needs-ab.md
printf '# Plan: needs-a\n\n- Order against the other open Plans:\n  - `base-a` (step 3): run it first. It defines the contract.\n  - `base-b`: both edit `src/c.ts`. Either order works.\n' > .plans/needs-a.md
git add .plans && git commit -qm 'plans with an order'
out=$(bash "$COORD" admit needs-ab); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q 'needs-ab waits for base-a, base-b' \
    && ok "admit holds a Plan that starts only after open changes land" || bad "after-landed hold (rc $rc): $out"
out=$(bash "$COORD" admit needs-a); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q 'needs-a waits for base-a' && ! echo "$out" | grep -q 'base-b' \
    && ok "admit holds on 'run it first' and ignores 'either order'" || bad "run-it-first hold (rc $rc): $out"
echo "$out" | grep -q -- '--after-ok base-a' && ok "the hold names its override" || bad "override hint: $out"
out=$(bash "$COORD" admit needs-ab --after-ok base-a); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q 'needs-ab waits for base-b' && ! echo "$out" | grep -q 'for base-a' \
    && ok "--after-ok lifts the hold for the named change only" || bad "after-ok one (rc $rc): $out"
out=$(bash "$COORD" admit needs-ab --after-ok base-a --after-ok base-b); rc=$?
[ "$rc" -eq 0 ] && ok "--after-ok on every predecessor admits the Plan" || bad "after-ok all (rc $rc): $out"
out=$(HERDR_ENV=1 HERDR_WORKSPACE_ID=w bash "$COORD" start run needs-a 2>&1); rc=$?
[ "$rc" -eq 4 ] && echo "$out" | grep -q 'needs-a waits for base-a' && ok "start keeps the hold" || bad "start hold (rc $rc): $out"
out=$(HERDR_ENV=1 HERDR_WORKSPACE_ID=w bash "$COORD" start run needs-a --after-ok base-a --model sonnet 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'model sonnet' && ok "start passes --after-ok to admit" || bad "start after-ok (rc $rc): $out"
rm -f "$STATE"/sessions/*
git rm -q .plans/base-a.md && git commit -qm 'land base-a'
out=$(bash "$COORD" admit needs-a); rc=$?
[ "$rc" -eq 0 ] && ok "admit lets the Plan start once its predecessor's Plan left main" || bad "after land (rc $rc): $out"
git rm -q .plans/base-b.md .plans/needs-a.md .plans/needs-ab.md && git commit -qm 'clean'
exec 7>&-

echo
echo "coordinate_test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
