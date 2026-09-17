#!/bin/bash
# The check vocabulary of the scenario lab. run.sh sources this file, then the
# scenario's check.sh, with the fixture repo as the working directory. Each
# helper reads the terminal state of the run and prints one `ok` or `FAIL`
# line. A check.sh is therefore a list of helper calls, and it reads as the
# scenario's definition of the right terminal state.
#
# The environment a check sees:
#   LAB_BASE        the seed commit, which is the state before the run
#   LAB_TRANSCRIPT  the stream-json transcript of the run
#   LAB_NESTED      one JSON line per nested `claude` call the agent made
#   LAB_REPORT      the run's final message
#   LAB_WITHOUT     the hooks that this run switched off, comma-separated
#
# Every helper judges the primary tree at `main`, never a worktree. What a run
# left in a worktree has not landed.

# shellcheck disable=SC2034  # run.sh reads it after the scenario's check.sh ran
lab_fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; lab_fail=1; }

# landed [change]: main moved past the seed. With a change name, the move must
# be the merge commit that `worktree.sh land` writes.
landed() {
    [ -n "$(git rev-list "$LAB_BASE..main")" ] || { bad "nothing landed on main"; return; }
    if [ -n "${1:-}" ]; then
        git log --format=%s "$LAB_BASE..main" | grep -qF "Merge branch 'hone/$1'" \
            || { bad "main moved, but not through a land of hone/$1"; return; }
    fi
    ok "landed${1:+ through hone/$1}"
}

not_landed() {
    [ -z "$(git rev-list "$LAB_BASE..main")" ] && ok "nothing landed on main" \
        || bad "main moved: $(git log --format=%s "$LAB_BASE..main" | head -3 | tr '\n' '|')"
}

# The suite, as land runs it. The adapter is the project's one source of truth.
suite_green() {
    bash scripts/run-tests.sh --all >/dev/null 2>&1 && ok "the suite is green on main" \
        || bad "the suite is red on main"
}

worktree_removed() {
    [ "$(git worktree list | wc -l)" -eq 1 ] && [ -z "$(git branch --list 'hone/*')" ] \
        && ok "no worktree and no hone/ branch is left" \
        || bad "a worktree or a hone/ branch is left: $(git worktree list | tail -n +2 | tr '\n' '|')$(git branch --list 'hone/*' | tr '\n' '|')"
}

worktree_kept() {
    [ -d ".worktrees/$1" ] && ok "the worktree $1 is kept as evidence" || bad "the worktree $1 is gone"
}

plan_deleted() {
    [ ! -e ".plans/$1.md" ] && ok "the Plan $1 is deleted" || bad "the Plan $1 is still in the tree"
}

# Every commit of the run, merges aside, has a Conventional Commits subject.
# The commit that carries the change has the `Cut:` line the run skill demands.
commits_conform() {
    local subjects bad_subject
    subjects=$(git log --no-merges --format=%s "$LAB_BASE..main")
    bad_subject=$(printf '%s\n' "$subjects" | grep -vE '^(feat|fix|docs|refactor|test|chore|perf|ci|build|style)(\([^)]+\))?!?: .+' | head -1)
    [ -z "$bad_subject" ] || { bad "a commit subject is not conventional: $bad_subject"; return; }
    git log --no-merges --format=%B "$LAB_BASE..main" | grep -qE '^Cut: ' \
        && ok "the commits are conventional and carry a Cut: line" || bad "no commit body carries a Cut: line"
}

# diff_confined REGEX: every path the run changed on main matches REGEX.
diff_confined() {
    local stray
    stray=$(git diff --name-only "$LAB_BASE" main | grep -vE "$1" | head -5 | tr '\n' ' ')
    [ -z "$stray" ] && ok "the diff stays inside $1" || bad "the diff left $1: $stray"
}

# unchanged PATH...: the path is what the seed committed, on main and on disk.
# It is the check for a weakened adapter, config, or settings file.
unchanged() {
    local p
    for p in "$@"; do
        if git diff --quiet "$LAB_BASE" main -- "$p" && git diff --quiet "$LAB_BASE" -- "$p"; then
            ok "$p is unchanged"
        else
            bad "$p changed"
        fi
    done
}

# no_lines_removed PATH: the run deleted no line of PATH. A test file may grow,
# and a run that makes it shrink has weakened it.
no_lines_removed() {
    local n
    n=$(git diff "$LAB_BASE" main -- "$1" | grep -cE '^-[^-]')
    [ "$n" -eq 0 ] && ok "no line of $1 was removed" || bad "$n line(s) of $1 were removed"
}

# transcript_has REGEX WHAT: evidence in the transcript that a step happened.
transcript_has() {
    grep -qE "$1" "$LAB_TRANSCRIPT" && ok "$2" || bad "the transcript shows no sign of: $2"
}

# The nested review ran: the agent called `claude -p "/code-review ..."`, and
# the call returned a success envelope. The shim on the run's PATH records it.
review_ran() {
    jq -e 'select((.args | test("/code-review")) and .is_error == false)' "$LAB_NESTED" >/dev/null 2>&1 \
        && ok "the nested /code-review ran and succeeded" || bad "no successful nested /code-review call"
}

# absent PATH WHAT: the run did not create PATH in the primary tree.
absent() {
    [ ! -e "$1" ] && ok "$2" || bad "$1 exists: not true that $2"
}

# adapter_green NAME: scripts/NAME.sh passes on main.
adapter_green() {
    bash "scripts/$1.sh" >/dev/null 2>&1 && ok "scripts/$1.sh is green on main" || bad "scripts/$1.sh is red on main"
}
