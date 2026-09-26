#!/bin/bash
# Unit cases for scripts/sql-rewrite.awk, the reader that decides whether a
# table rewrite loses data. test/e2e_land_test.sh drives it through land; this
# pins the loss paths one by one. Every case but the "ok" ones must come out
# "no", because a wrong "ok" lands data loss unattended.
# Run: bash test/sql_rewrite_test.sh
set -uo pipefail

AWK="$(cd "$(dirname "$0")/.." && pwd)/scripts/sql-rewrite.awk"
pass=0; fail=0

# case <name> <want: ok or the start of the reason> <prior sql> <target sql>
case_() {
    local got
    got=$( { printf '\001prior\tm/0001.sql\n%s\n\001target\tm/0002.sql\n%s\n' "$3" "$4"; } \
        | awk -f "$AWK" | head -n 1)
    local verdict="${got%%$'\t'*}" reason="${got##*$'\t'}" hit=""
    if [ "$2" = ok ]; then
        [ "$verdict" = ok ] && hit=yes
    else
        [ "$verdict" = no ] && case "$reason" in "$2"*) hit=yes ;; esac
    fi
    if [ -n "$hit" ]; then
        pass=$((pass+1))
    else
        fail=$((fail+1)); printf '  FAIL %s: want "%s", got "%s"\n' "$1" "$2" "$got"
    fi
}

P='CREATE TABLE u (id INTEGER, n TEXT);'
NEW='CREATE TABLE un (id INTEGER, n TEXT);'
TAIL='DROP TABLE u;
ALTER TABLE un RENAME TO u;'
COPY='INSERT INTO un SELECT id, n FROM u;'

case_ plain ok "$P" "$NEW
$COPY
$TAIL"
case_ star ok "$P" "$NEW
INSERT INTO un SELECT * FROM u;
$TAIL"
case_ quoting ok "$P" "/* a; b */ CREATE TABLE \"un\" (id INTEGER, n TEXT DEFAULT 'a;b'); -- c; d
INSERT INTO [un] (\"id\", \`n\`) SELECT u.id, u.n FROM main.u;
DROP TABLE IF EXISTS \"u\";
ALTER TABLE un RENAME TO u;"
case_ case-insensitive ok "$P" "create table UN (ID integer, N text);
insert into un select Id, n from U;
drop table U;
alter table Un rename to u;"
case_ renamed-column ok "$P
ALTER TABLE u RENAME COLUMN n TO name;" "CREATE TABLE un (id INTEGER, name TEXT);
INSERT INTO un SELECT id, name FROM u;
$TAIL"
case_ insert-or-ignore "the copy is not a plain INSERT INTO" "$P" "$NEW
INSERT OR IGNORE INTO un SELECT id, n FROM u;
$TAIL"
case_ on-conflict "un has an ON CONFLICT clause" "$P" "CREATE TABLE un (id INTEGER PRIMARY KEY ON CONFLICT REPLACE, n TEXT);
$COPY
$TAIL"
case_ distinct "the copy selects DISTINCT rows" "$P" "$NEW
INSERT INTO un SELECT DISTINCT id, n FROM u;
$TAIL"
case_ limit "the copy filters or joins rows (LIMIT" "$P" "$NEW
INSERT INTO un SELECT id, n FROM u LIMIT 10;
$TAIL"
case_ join "the copy filters or joins rows (JOIN" "$P" "$NEW
INSERT INTO un SELECT u.id, u.n FROM u JOIN v ON v.id = u.id;
$TAIL"
case_ computed "the copy computes a value" "$P" "$NEW
INSERT INTO un SELECT id, substr(n, 1, 3) FROM u;
$TAIL"
case_ swapped "the copy moves id into n" "$P" "$NEW
INSERT INTO un (n, id) SELECT id, n FROM u;
$TAIL"
case_ update-after-copy "another statement writes to u or un" "$P" "$NEW
$COPY
UPDATE un SET n = NULL;
$TAIL"
case_ trigger-copy "a trigger on un exists during the copy" "$P" "$NEW
CREATE TRIGGER tr AFTER INSERT ON x BEGIN INSERT INTO un SELECT id, n FROM u; UPDATE y SET a = CASE WHEN 1 THEN 2 END; END;
$TAIL"
case_ drop-shares-line "the DROP of u does not stand alone" "$P" "$NEW
$COPY
DROP TABLE u; CREATE INDEX x ON un(n);
ALTER TABLE un RENAME TO u;"
case_ down-section "an earlier migration has a down or rollback section" "$P
-- +goose Down
DROP TABLE u;" "$NEW
$COPY
$TAIL"
case_ multi-add "the columns of u are unknown" "$P
ALTER TABLE u ADD COLUMN a INT, ADD COLUMN b INT;" "CREATE TABLE un (id INTEGER, n TEXT, a INT);
INSERT INTO un SELECT id, n, a FROM u;
$TAIL"
case_ create-as-select "the columns of u are unknown" "CREATE TABLE u AS SELECT 1 AS id;" "CREATE TABLE un (id INTEGER);
INSERT INTO un SELECT id FROM u;
$TAIL"
case_ generated "the columns of u are unknown" "CREATE TABLE u (id INTEGER, n TEXT, m TEXT GENERATED ALWAYS AS (n) STORED);" "$NEW
$COPY
$TAIL"
case_ set-null-fk "a foreign key at m/0001.sql:2 references u with ON DELETE SET" "$P
CREATE TABLE c (u_id INTEGER REFERENCES u (id) ON DELETE SET NULL);" "$NEW
$COPY
$TAIL"
case_ star-reorder "the copy uses * and column 1" "$P" "CREATE TABLE un (n TEXT, id INTEGER);
INSERT INTO un SELECT * FROM u;
$TAIL"
case_ drop-twice "it drops u more than once" "$P" "$NEW
$COPY
DROP TABLE u;
$TAIL"

printf 'sql_rewrite_test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
