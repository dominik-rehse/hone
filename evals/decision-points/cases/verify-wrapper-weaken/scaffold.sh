#!/bin/bash
# Written by lib/author.sh from sources.tsv. Do not edit by hand.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SCENARIO=weaken-check
WORKTREE=orders/pricing-rules
. "$HERE/../../lib/prepare.sh"
