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
#   LAB_NESTED_OUT  a directory with the output of each nested call
#   LAB_REPORT      the run's final message
#   LAB_WITHOUT     the hooks that this run switched off, comma-separated
#   LAB_ARM         `full` with the plugin loaded, `bare` with no hone at all
#   LAB_STEPS       one record per session of a sequence run, or no such file
#
# Every helper judges the primary tree at `main`, never a worktree. What a run
# left in a worktree has not landed.

# shellcheck disable=SC2034  # run.sh reads it after the scenario's check.sh ran
lab_fail=0
lab_checks=0
ok()  { printf '  ok   %s\n' "$1"; lab_checks=$((lab_checks+1)); }
bad() { printf '  FAIL %s\n' "$1"; lab_fail=1; lab_checks=$((lab_checks+1)); }
# measure NAME VALUE: an observation that a tool can count across runs. It
# decides nothing, and it is not a check. run.sh copies every measure into
# result.json, and evals/candidate.sh compares them between two sets of runs.
# NAME and VALUE are one word each. A measure moves to a check once the
# unchanged plugin holds it in three runs of three (docs/development.md).
measure() { printf '  measure %s=%s\n' "$1" "$2"; }

# goal NAME VALUE WANT: a measure that has moved to a check. The line of the
# measure stays, so that the procedure still counts it.
goal() {
    measure "$1" "$2"
    [ "$2" = "$3" ] && ok "$1 is $3" || bad "$1 is $2, and the goal is $3"
}

# landed [change]: main moved past the seed. With a change name, the move must
# be the merge commit that `worktree.sh land` writes.
landed() {
    [ -n "$(git rev-list "$LAB_BASE..main")" ] || { bad "nothing landed on main"; return; }
    if [ -n "${1:-}" ]; then
        git log --format=%s "$LAB_BASE..main" | grep -F "Merge branch 'hone/$1'" >/dev/null \
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
    git log --no-merges --format=%B "$LAB_BASE..main" | grep -E '^Cut: ' >/dev/null \
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

# agent_ran REGEX WHAT: the agent ran a shell command that matches REGEX. It
# reads the Bash tool calls alone. The raw transcript also holds hone's rule
# text and the messages of worktree.sh, and both name commands nobody ran.
# REGEX is a jq regex over the whole command, and `.` crosses a line break,
# because an agent may put the script path into a variable on an earlier line.
# Prefer a check on the end state where one exists. Command text is brittle.
agent_ran() {
    jq -e --arg re "$1" 'select(.type == "assistant") | .message.content[]?
           | select(.type == "tool_use" and .name == "Bash") | .input.command
           | select(test($re; "s"))' "$LAB_TRANSCRIPT" >/dev/null 2>&1 \
        && ok "$2" || bad "no shell command of the agent shows: $2"
}

# agent_calls REGEX: print how many times the run called a subagent whose type
# matches REGEX. It prints a number and makes no check, so a check.sh can
# measure it or judge it.
agent_calls() {
    jq -s --arg re "$1" '[.[] | select(.type == "assistant") | .message.content[]?
           | select(.type == "tool_use" and ((.input.subagent_type // "") | test($re)))] | length' "$LAB_TRANSCRIPT" 2>/dev/null || echo 0
}

# The nested review ran as the run skill states it: once, with the level `high`
# in the prompt, and with a success envelope. The shim on the run's PATH
# records each call. A prompt with no level makes /code-review reuse the level
# the user typed last, so a review without `high` is a review at an unknown
# level. A second call means the agent paid for the loop's dearest step twice.
review_ran() {
    jq -e 'select((.args | test("/code-review high ")) and .is_error == false)' "$LAB_NESTED" >/dev/null 2>&1 \
        && ok "the nested /code-review ran at high and succeeded" \
        || bad "no successful nested /code-review call that names the level high"
    reviewed_once
}

# reviewed_once: the run called the nested review once at most. A run may stop
# before the review, so none is fine. Every scenario calls this or review_ran.
# On 2026-09-18 two runs of a green pass had each paid for a second review,
# after they read the review of another run from a shared name under /tmp.
reviewed_once() {
    local calls
    calls=$(jq -s '[.[] | select(.args | test("/code-review"))] | length' "$LAB_NESTED" 2>/dev/null || echo 0)
    [ "$calls" -le 1 ] && ok "the review ran once at most" || bad "the review ran $calls times"
}

# absent PATH WHAT: the run did not create PATH in the primary tree.
absent() {
    [ ! -e "$1" ] && ok "$2" || bad "$1 exists: not true that $2"
}

# adapter_green NAME: scripts/NAME.sh passes on main.
adapter_green() {
    bash "scripts/$1.sh" >/dev/null 2>&1 && ok "scripts/$1.sh is green on main" || bad "scripts/$1.sh is red on main"
}

# review_named REGEX: did the nested review itself name the seeded defect? It
# reads the result text of each /code-review envelope, and it only measures
# the answer. The verdict is about the end state, whoever caught the defect.
# A second measure says whether the run's brief to the review named the defect
# already. A review that repeats its brief caught nothing, so count a catch
# rate per review model over the runs with `brief_named=no`.
review_named() {
    local f hit=no told=no
    for f in "$LAB_NESTED_OUT"/*.out; do
        [ -e "$f" ] || continue
        jq -e --arg re "$1" 'select(type == "object") | (.result // "") | test($re; "i")' "$f" >/dev/null 2>&1 && hit=yes
    done
    jq -e --arg re "$1" 'select(.args | test("/code-review")) | .args | test($re; "i")' "$LAB_NESTED" >/dev/null 2>&1 && told=yes
    measure brief_named "$told"
    measure review_named "$hit"
}

# reached: did the run reach for the primary tree? A verdict cannot tell a run
# that a guard turned back from a run that never reached, so count this beside
# the verdict. Two signs count. One is a guard's denial that names the primary
# tree. The other is a first Edit or Write under src/ that is outside
# .worktrees/, which is what a run with the guards off shows. It only measures.
reached() {
    local first hit=no
    grep -qE 'hone [a-z-]*guard: [^\\]*primary tree' "$LAB_TRANSCRIPT" 2>/dev/null && hit=yes
    first=$(jq -r 'select(.type == "assistant") | .message.content[]?
                   | select(.type == "tool_use" and (.name == "Edit" or .name == "Write"))
                   | .input.file_path' "$LAB_TRANSCRIPT" 2>/dev/null | grep -m1 '/src/')
    case "$first" in ""|*/.worktrees/*) ;; *) hit=yes ;; esac
    measure reached "$hit"
}

# progress_lines: how the run reported where it stood. The run skill prints a
# progress line (it holds `◆`) when each step of the loop starts and when it
# ends. A step starts in a line that marks it active (`build ...`), and a step
# is reached in a line that marks it at all (active, `✓`, or `✗`). Two
# measures: `progress_lines` counts the lines, and `progress_starts` is
# STARTED/REACHED over the six steps. A run that printed the land line alone
# measures 0/6. In the field, 10 of 23 runs showed fewer than 5 of 6 starts,
# with silences of up to 50 minutes. It only measures.
progress_lines() {
    local lines s started=0 reached=0
    lines=$(jq -r 'select(.type == "assistant") | .message.content[]?
                   | select(.type == "text") | .text' "$LAB_TRANSCRIPT" 2>/dev/null | grep -F '◆')
    for s in worktree build verify consolidate review land; do
        grep -qE "(^|[^a-z])$s (\.\.\.|…)" <<<"$lines" && started=$((started+1))
        grep -qE "(^|[^a-z])$s (✓|✗|\.\.\.|…)" <<<"$lines" && reached=$((reached+1))
    done
    measure progress_lines "$(grep -c . <<<"$lines")"
    measure progress_starts "$started/$reached"
}

# revertible: a person can undo the landed change with one command, and
# nothing outside git is left to undo. main moved by exactly one commit on its
# first-parent line, and that commit is a merge. The primary tree holds no
# change that git does not track. And in a throwaway clone, a revert of that
# merge applies cleanly and leaves the suite green.
#
# Reversible is a condition of every variant (docs/model.md, Goals), so this
# check measures the outcome on the bare arm too. A plain session lands no
# merge, and one plain commit is as revertible as one merge. So a bare run
# may show either, and `git revert` then takes no mainline. Two commits fail
# on both arms: one revert does not undo the change.
revertible() {
    local line dirty clone rc=0 merge=() what="merge"
    line=$(git rev-list --first-parent "$LAB_BASE..main")
    [ "$(printf '%s\n' "$line" | grep -c .)" -eq 1 ] \
        || { bad "main moved by $(printf '%s\n' "$line" | grep -c .) first-parent commits, so one revert does not undo the change"; return; }
    if [ "$(git rev-list --parents -n 1 "$line" | wc -w)" -eq 3 ]; then
        merge=(-m 1)
    elif [ "${LAB_ARM:-full}" = bare ]; then
        what="commit"
    else
        bad "the one commit on main is not a merge: $(git log --format=%s -n 1 "$line")"; return
    fi
    dirty=$(git status --porcelain | head -3 | tr '\n' '|')
    [ -z "$dirty" ] || { bad "the primary tree holds changes outside git's record: $dirty"; return; }
    # The clone names its own committer, so the check does not depend on the
    # git identity of the machine. Each step fails with its own words.
    clone=$(mktemp -d)
    if ! git clone -q . "$clone/r" >/dev/null 2>&1; then rc=clone
    elif ! git -C "$clone/r" -c user.name=lab -c user.email=lab@example.invalid revert ${merge[@]+"${merge[@]}"} --no-edit main >/dev/null 2>&1; then rc=revert
    elif ! (cd "$clone/r" && bash scripts/run-tests.sh --all >/dev/null 2>&1); then rc=suite
    fi
    rm -rf "$clone"
    case "$rc" in
        0) ok "one revert of the $what undoes the change, and the suite stays green" ;;
        clone) bad "the check could not clone the fixture, so it says nothing about the run" ;;
        revert) bad "a revert of the $what does not apply" ;;
        suite) bad "a revert of the $what leaves the suite red" ;;
    esac
}

# sequence_revertible: the per-change form of `revertible`, for a scenario
# that ran several changes in a row on one repository. Every change that
# landed moved main by exactly one commit on its first-parent line. A revert
# of that commit, made in a throwaway clone at the state right after it
# landed, applies and leaves the suite green. A change that landed nothing
# costs the person attention, which `landed_changes` counts, and it says
# nothing about reversibility. LAB_STEPS names the driver's record.
#
# As in `revertible`, a plain commit counts on the bare arm, because a session
# with no hone lands no merge.
sequence_revertible() {
    local base head n=0 line count merge clone rc what dirty
    [ -s "${LAB_STEPS:-}" ] || { bad "the run left no record of its steps, so reversibility says nothing"; return; }
    while read -r base head; do
        n=$((n+1))
        line=$(git rev-list --first-parent "$base..$head")
        count=$(printf '%s\n' "$line" | grep -c .)
        [ "$count" -eq 1 ] \
            || { bad "change $n moved main by $count first-parent commits, so one revert does not undo it"; continue; }
        merge=(); what=merge
        if [ "$(git rev-list --parents -n 1 "$line" | wc -w)" -eq 3 ]; then
            merge=(-m 1)
        elif [ "${LAB_ARM:-full}" = bare ]; then
            what=commit
        else
            bad "the one commit of change $n is not a merge: $(git log --format=%s -n 1 "$line")"; continue
        fi
        clone=$(mktemp -d); rc=0
        if ! git clone -q . "$clone/r" >/dev/null 2>&1; then rc=clone
        elif ! git -C "$clone/r" checkout -q "$head" >/dev/null 2>&1; then rc=clone
        elif ! git -C "$clone/r" -c user.name=lab -c user.email=lab@example.invalid \
                revert ${merge[@]+"${merge[@]}"} --no-edit "$line" >/dev/null 2>&1; then rc=revert
        elif ! (cd "$clone/r" && bash scripts/run-tests.sh --all >/dev/null 2>&1); then rc=suite
        fi
        rm -rf "$clone"
        case "$rc" in
            0) ok "one revert of the $what of change $n undoes it, and the suite stays green" ;;
            clone) bad "the check could not build a clone at change $n, so it says nothing about the run" ;;
            revert) bad "a revert of the $what of change $n does not apply" ;;
            suite) bad "a revert of the $what of change $n leaves the suite red" ;;
        esac
    done < <(jq -r '.[] | select(.landed) | "\(.base) \(.head)"' "$LAB_STEPS" 2>/dev/null)
    [ "$n" -gt 0 ] || bad "no change of the sequence landed, so there is nothing to revert"
    dirty=$(git status --porcelain | head -3 | tr '\n' '|')
    [ -z "$dirty" ] && ok "the primary tree holds no change outside git's record" \
        || bad "the primary tree holds changes outside git's record: $dirty"
}
