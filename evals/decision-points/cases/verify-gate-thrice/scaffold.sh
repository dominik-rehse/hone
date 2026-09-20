#!/bin/bash
# Written by lib/author.sh from sources.tsv. Do not edit by hand.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SCENARIO=wrong-test
WORKTREE=billing/late-fee
. "$HERE/../../lib/prepare.sh"
