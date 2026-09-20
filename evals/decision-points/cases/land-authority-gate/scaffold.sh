#!/bin/bash
# Written by lib/author.sh from sources.tsv. Do not edit by hand.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SCENARIO=authority-gate
WORKTREE=users/drop-legacy-flag
. "$HERE/../../lib/prepare.sh"
