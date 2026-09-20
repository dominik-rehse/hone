#!/bin/bash
# Build the machine-made half of every decision-point case from `sources.tsv`.
#
# A case has two halves. This script writes the half that a recorded lab
# session decides: `history.tmpl.jsonl`, the `files/` overlay, `scaffold.sh`,
# and `case.yaml`. The other half is judgment, and a person writes it:
# `prompt.md` and `graders/*.md`. Those are never touched here.
#
# `sources.tsv` is the provenance. One line per case, tab separated:
#
#   case    scenario    worktree    cut    turns    sandbox
#
#   case       the directory name under cases/
#   scenario   the lab scenario, which also names the fixture tarball
#   worktree   the worktree the recorded session held, or `-` for none
#   cut        how many kept rows to keep (see `history.py show --kept`)
#   turns      max_turns for the case
#   sandbox    the lab sandbox that holds the recording
#
# The sandbox is under /var/tmp/hone-lab/ and it does not survive a reboot.
# A case that has to be rebuilt needs its scenario run again. The README says
# how.
#
# Usage: bash lib/author.sh [case ...]      (no argument: every case)
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1  # no bytecode cache in the repository
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
TSV="$ROOT/sources.tsv"
[ -f "$TSV" ] || { echo "no $TSV" >&2; exit 2; }

want=" $* "
rc=0
while IFS=$'\t' read -r name scenario worktree cut turns sandbox; do
    case "$name" in ''|'#'*) continue;; esac
    [ "$#" -eq 0 ] || [[ "$want" == *" $name "* ]] || continue

    log=$(ls "$sandbox"/home/.claude/projects/*-repo/*.jsonl 2>/dev/null | head -1)
    if [ -z "$log" ]; then
        echo "$name: no session log under $sandbox (run the scenario again)" >&2
        rc=1; continue
    fi
    dir="$ROOT/cases/$name"
    mkdir -p "$dir/graders"
    rm -rf "$dir/files"

    # A session that never loaded a skill, such as `hand-merge`, carries no
    # base-directory line. The lab's own layout gives both paths instead.
    python3 "$HERE/history.py" extract "$log" --upto "$cut" \
        --plugin-root "$sandbox/plugin" --workspace "$sandbox/repo" \
        --out "$dir/history.tmpl.jsonl" --scenario "$scenario" --point "$name" \
        || { rc=1; continue; }
    python3 "$HERE/history.py" overlay "$log" --upto "$cut" --out "$dir/files" \
        || { rc=1; continue; }

    {
        echo '#!/bin/bash'
        echo '# Written by lib/author.sh from sources.tsv. Do not edit by hand.'
        echo 'set -uo pipefail'
        echo 'HERE=$(cd "$(dirname "$0")" && pwd)'
        echo "SCENARIO=$scenario"
        [ "$worktree" = "-" ] || echo "WORKTREE=$worktree"
        echo '. "$HERE/../../lib/prepare.sh"'
    } > "$dir/scaffold.sh"

    # The tag is the step of the loop, taken from the case name. `--tag` is
    # repeatable, where `--case` takes one glob, so a tag is how a caller
    # picks the cases of one step.
    cat > "$dir/case.yaml" <<EOF
# Written by lib/author.sh from sources.tsv. Do not edit by hand.
schema_version: "1.1"
name: $name
description: "$scenario, cut at kept row $cut"
tags: [${name%%-*}, $scenario]
runs: 3
context:
  scaffold_script: scaffold.sh
  history_file: session.jsonl
execution:
  max_turns: $turns
  timeout_seconds: 600
  allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Task]
EOF
    [ -f "$dir/prompt.md" ] || printf 'Continue.\n' > "$dir/prompt.md"
    echo "$name: built from $(basename "$sandbox")"
done < "$TSV"

python3 "$HERE/history.py" scrub-check "$ROOT"/cases/*/history.tmpl.jsonl || rc=1
exit "$rc"
