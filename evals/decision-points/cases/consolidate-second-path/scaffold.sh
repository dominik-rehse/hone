#!/bin/bash
# Written by lib/author.sh from sources.tsv. Do not edit by hand.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SCENARIO=parallel-paths
WORKTREE=pricing/round-half-up
. "$HERE/../../lib/prepare.sh"
