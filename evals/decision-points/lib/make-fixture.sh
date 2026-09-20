#!/bin/bash
# Build the seeded tree of one lab scenario into fixtures/<scenario>.tar.gz.
#
# A decision-point case resumes a recorded lab session, so its workspace must
# hold the repository that the session worked in. The lab sandbox keeps the
# repository in its FINAL state, and the file `base` beside it names the commit
# that the seed left. `git archive` of that commit is the state the run started
# from, and the case's `prepare.sh` replays what the run wrote after it.
#
# The tarball carries no `.git`, because `prepare.sh` makes a fresh one. That
# keeps it small: about 3 KB for a lab fixture.
#
# Usage: bash lib/make-fixture.sh /var/tmp/hone-lab/<run>/<scenario> <name>
set -uo pipefail
SB="${1:?usage: make-fixture.sh <lab sandbox scenario dir> <name>}"
NAME="${2:?usage: make-fixture.sh <lab sandbox scenario dir> <name>}"
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/../fixtures"

[ -f "$SB/base" ] || { echo "no $SB/base: not a lab sandbox" >&2; exit 2; }
[ -d "$SB/repo" ] || { echo "no $SB/repo" >&2; exit 2; }
BASE=$(cat "$SB/base")

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git -C "$SB/repo" archive "$BASE" | tar -x -C "$TMP" || exit 2

mkdir -p "$OUT"
tar -czf "$OUT/$NAME.tar.gz" --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime='2026-01-01 00:00:00' -C "$TMP" . || exit 2
echo "$OUT/$NAME.tar.gz: $(du -b "$OUT/$NAME.tar.gz" | cut -f1) bytes, base $BASE"
