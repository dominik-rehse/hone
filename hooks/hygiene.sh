#!/bin/bash
# hone's hygiene checks: deterministic checks that keep the durable layer from
# silently growing. scripts/worktree.sh SOURCES this file, and nothing executes
# it directly. It defines functions only, and it has no side effects at source
# time. Two subcommands call it:
#
#   worktree.sh hygiene <change>   the checks scoped to what one change touched
#   worktree.sh attention          what the person should know about the
#                                  primary tree, shown at session start and at
#                                  the end of a run or a batch
#
# The checks, by their old numbers:
#
#   1. Leftover Plan: a .plans/<change>.md whose change has LANDED: no
#      worktree, plus positive evidence the change concluded. The merge commit
#      land writes (its fixed -m format makes the grep exact) or a surviving
#      hone/<change> branch that is fully merged AND once carried a commit of
#      its own into the primary branch. Consolidate should have deleted it.
#      "No worktree" alone is NOT evidence: that is the normal plan→run gap.
#      Pending Plans get one aggregate line, only while no coordinator is
#      active (see hy_pending_quiet). <change> may be nested
#      (auth/refresh-token), so the scan recurses. A markdown file inside
#      .plans/<slug>/ beside a <slug>.md is one of that Plan's references.
#   2. Oversized Note: a docs/notes/<area>.md over the size cap (a Note is a
#      map + one invariant, not a spec: half a screen).
#   3. Orphan Note: a docs/notes/<area>.md with no corresponding src/<area>/.
#   4. Change that cuts nothing: the change's whole diff against its merge
#      base has zero deletions. "Every cycle removes something" is the model's
#      principle 4. A hard rule would incentivize token deletions, so the
#      finding offers real cuts or a Cut: line that says why nothing could go.
#   5. Landed branch left behind: a hone/* branch fully merged into the
#      primary tree's HEAD with no worktree attached.
#   6. Broken Governs link: a Decision or Note declaring `Governs: <path>`
#      whose path no longer exists. Only path-shaped tokens (containing "/")
#      count, so the check is exact.
#   7. Durable truth stranded in harness memory: a `type: project` memory file
#      under the harness's per-project memory directory. That store is
#      per-user, uncommitted, and invisible to garden. The file belongs to the
#      person, so hone names it and never touches it.
#   8. Undated spike entry: an entry directly under docs/spikes/ whose name
#      does not open with YYYY-MM-DD, of any type, file or directory. The
#      date is the whole signal that a spike is frozen history.
#   9. Broken relative link: a markdown link in a Decision or Note whose
#      target does not resolve from the doc's directory. A target with a URI
#      scheme, an #anchor, and a link inside code are not files.
#  10. Stale claim: a refs/hone/claim/<change> ref this clone holds (shared
#      mode) with no .worktrees/<change>.
#  11. Oversized area: a src/<area>/ whose tracked text files hold more lines
#      than HONE_AREA_MAX_LINES (default 3000). A generated file does not
#      count (see hy_area_files).

# Note size cap: lines. "Half a screen".
HY_NOTE_MAX_LINES=40

# ------------------------------------------------------------ tree access
#
# The change-scoped checks read one tree: a directory (HY_REV empty), or a
# revision of the repository at HY_DIR (HY_REV set). worktree.sh hygiene
# sets both: the worktree with its uncommitted files, else the branch.
HY_DIR="."
HY_REV=""

# Normalize a relative path lexically ("a/b/../c" -> "a/c"). Prints nothing
# for a path that climbs out of the tree.
hy_norm() {
    local p
    p=$(realpath -m -s "/hy-root/$1" 2>/dev/null) || return 0
    case "$p" in
        /hy-root) printf '.\n' ;;
        /hy-root/*) printf '%s\n' "${p#/hy-root/}" ;;
    esac
}

# True when path $1 (relative to the tree root) exists in the tree.
hy_exists() {
    if [ -z "$HY_REV" ]; then
        [ -e "$HY_DIR/$1" ]
    else
        local p
        p=$(hy_norm "$1")
        [ -n "$p" ] || { [ -e "$HY_DIR/$1" ]; return; }
        [ "$p" = . ] && return 0
        git -C "$HY_DIR" cat-file -e "$HY_REV:$p" 2>/dev/null
    fi
}

# True when path $1 is a directory in the tree.
hy_is_dir() {
    if [ -z "$HY_REV" ]; then
        [ -d "$HY_DIR/$1" ]
    else
        [ "$(git -C "$HY_DIR" cat-file -t "$HY_REV:${1%/}" 2>/dev/null)" = tree ]
    fi
}

# Print the contents of file $1 of the tree.
hy_cat() {
    if [ -z "$HY_REV" ]; then
        cat -- "$HY_DIR/$1" 2>/dev/null
    else
        git -C "$HY_DIR" show "$HY_REV:$1" 2>/dev/null
    fi
}

# ------------------------------------------------------------ the checks

# 2. Print the line count of Note $1 when it is over the cap.
hy_note_oversized() {
    local lines
    lines=$(hy_cat "$1" | wc -l | tr -d '[:space:]')
    [ "${lines:-0}" -gt "$HY_NOTE_MAX_LINES" ] && printf '%s\n' "$lines"
}

# 8. True when spike entry name $1 opens with a date.
hy_spike_dated() {
    case "$1" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) return 0 ;;
    esac
    return 1
}

# 6. Print each path on doc $1's Governs: line that does not exist. A glob
# expands against $2 (the directory that holds the doc's tree).
hy_governs_broken() {
    local doc="$1" root="${2:-$HY_DIR}" tmp tok
    tmp=$(mktemp) || return 0
    hy_cat "$doc" > "$tmp"
    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        hy_exists "$tok" || printf '%s\n' "$tok"
    done < <(hone_governs_paths "$tmp" "$root")
    rm -f "$tmp"
}

# 9. The link targets of a markdown text on stdin. The awk drops fenced code
# blocks and inline code spans first, because a link shown as code is an
# example: one Decision that quotes `[x](javascript:…)` printed a finding on
# every stop of every session.
hy_link_targets() {
    awk '
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        { gsub(/``[^`]*``/, ""); gsub(/`[^`]*`/, ""); print }
    ' 2>/dev/null | grep -oE '\]\([^)]+\)' | sed 's/^](//; s/)$//'
}

# 9. Print each relative link target of doc $1 that does not resolve from the
# doc's directory. A title after the target and a #fragment are stripped.
hy_links_broken() {
    local doc="$1" target dir
    dir=$(dirname "$doc")
    while IFS= read -r target; do
        case "$target" in
            ''|'#'*|/*) continue ;;
        esac
        # Any URI scheme: https:, mailto:, javascript:, data:, tel:.
        grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*:' <<<"$target" && continue
        target=${target%%#*}      # drop a fragment
        target=${target%% *}      # drop a link title
        [ -n "$target" ] || continue
        hy_exists "$dir/$target" || printf '%s\n' "$target"
    done < <(hy_cat "$doc" | hy_link_targets)
}

# 11. The files of area $1 that count toward its size, NUL-separated: tracked
# (or, in a worktree, new and not ignored), and not generated. A generated
# output.css was 11,699 of 17,764 lines in one area, and an agent never reads
# such a file to work in the area. Generated means marked linguist-generated
# in .gitattributes, or a header in its first five lines that says
# @generated, DO NOT EDIT, or auto-generated.
hy_area_files() {
    local f area="$1"
    if [ -z "$HY_REV" ]; then
        git -C "$HY_DIR" ls-files -z --cached --others --exclude-standard -- ":(literal)$area" \
            ":(exclude,literal,attr:linguist-generated)$area" \
            ":(exclude,literal,attr:linguist-generated=true)$area" 2>/dev/null \
            | while IFS= read -r -d '' f; do
                  hone_generated_header "$HY_DIR/$f" && continue
                  printf '%s\0' "$f"
              done
    else
        git -C "$HY_DIR" ls-tree -r -z --name-only "$HY_REV" -- "$area" 2>/dev/null \
            | while IFS= read -r -d '' f; do
                  [ -n "$(git -C "$HY_DIR" check-attr --source="$HY_REV" linguist-generated -- "$f" 2>/dev/null \
                      | grep -E ': (set|true)$')" ] && continue
                  hone_generated_header <(hy_cat "$f") && continue
                  printf '%s\0' "$f"
              done
    fi
}

# 11. Print the line count of area $1 (src/<area>): every counted text file.
# A binary file has no lines to read, so it does not count.
hy_area_lines() {
    local f n total=0
    if [ -z "$HY_REV" ]; then
        hy_area_files "$1" | (cd "$HY_DIR" && xargs -0 -r grep -I -c '' -- 2>/dev/null) \
            | awk -F: '{ n += $NF } END { print n + 0 }'
        return 0
    fi
    while IFS= read -r -d '' f; do
        n=$(hy_cat "$f" | grep -I -c '' 2>/dev/null)
        total=$((total + ${n:-0}))
    done < <(hy_area_files "$1")
    printf '%s\n' "$total"
}

# 1. A surviving branch is evidence of a landing only when it once carried a
# commit of its own into the primary branch. `git branch --merged HEAD` alone
# is not that: a branch is merged into itself, and a fresh hone/<change>
# points at a commit the primary branch already had (2026-09-19 probe).
# The test: the branch tip must sit OFF the primary branch's first-parent
# line. land merges a change, so its commits are on no first-parent line.
hy_branch_carried_work() {
    local branch="$1" tip common primary
    tip=$(git rev-parse --verify -q "$branch") || return 1
    common=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
    primary=$(git -C "$common/.." rev-parse --abbrev-ref HEAD 2>/dev/null)
    [ -n "$primary" ] && [ "$primary" != HEAD ] || return 1
    # No quiet reader in the pipeline: grep -q would quit early, and under
    # pipefail the write end's SIGPIPE would read as no match.
    [ -z "$(git rev-list --first-parent "$primary" 2>/dev/null | grep -xF "$tip")" ]
}

# 1. The pending-Plans line is for a person with no coordinator. A
# coordinator starts runs itself, so "run /hone:run" is wrong for it and for
# the sessions it watches: 149 such lines reached one coordinator in one
# batch. A coordinator is active when scripts/coordinate.sh watches a
# session, when a wait of it is alive, or when session $1 once waited (its
# cursor file). Run in the primary tree.
hy_pending_quiet() {
    local session="${1:-}" common st f pid
    common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 1
    st="$common/hone-coordinate"
    [ -d "$st" ] || return 1
    for f in "$st"/sessions/*; do
        [ -f "$f" ] && return 0
    done
    case "$session" in
        ''|*/*|.*) ;;
        *) [ -f "$st/cursor.$session" ] || [ -f "$st/wait.$session.pid" ] && return 0 ;;
    esac
    for f in "$st"/wait.*.pid; do
        [ -f "$f" ] || continue
        pid=$(cat "$f" 2>/dev/null)
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 0
    done
    return 1
}

# 1. Run in the primary tree. Print "landed\t<plan>\t<evidence>" per leftover
# Plan of a landed change, and "pending\t<count>" when Plans wait.
hy_plans() {
    [ -d .plans ] || return 0
    local plan change attached pending=0 landed merges merged
    attached=$(git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p')
    # One walk of history and one branch listing for every Plan: a walk per
    # Plan took 1.8 s on a repository of 2,000 commits and 20 Plans, and the
    # SessionStart hook has 5 s.
    merges=$(git log --fixed-strings --grep="Merge branch 'hone/" --format=%B 2>/dev/null \
        | grep -oE "Merge branch 'hone/[^']+'" | sed "s/^Merge branch 'hone\///; s/'\$//" | sort -u)
    merged=$(git branch --merged HEAD --format='%(refname:short)' 2>/dev/null)
    while IFS= read -r plan; do
        [ -f "$(dirname "$plan").md" ] && continue    # a Plan's reference
        change=${plan#.plans/}
        change=${change%.md}
        # Active work: the change has a worktree.
        [ -d ".worktrees/$change" ] && continue
        grep -qxF "hone/$change" <<<"$attached" && continue
        landed=""
        if grep -qxF "$change" <<<"$merges"; then
            landed="its landing merge commit is in history"
        elif grep -qxF "hone/$change" <<<"$merged" \
             && hy_branch_carried_work "hone/$change"; then
            landed="branch hone/${change} is fully merged"
        fi
        if [ -n "$landed" ]; then
            printf 'landed\t%s\t%s\n' "$plan" "$landed"
        else
            pending=$((pending+1))
        fi
    done < <(find .plans -type f -name '*.md' 2>/dev/null | sort)
    [ "$pending" -gt 0 ] && printf 'pending\t%s\n' "$pending"
    return 0
}

# 5. Run in the primary tree. Print each hone/* branch fully merged into HEAD
# with no worktree attached.
hy_merged_branches() {
    local attached b
    attached=$(git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p')
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        grep -qxF "$b" <<<"$attached" && continue   # active work
        printf '%s\n' "$b"
    done < <(git branch --merged HEAD --format='%(refname:short)' 2>/dev/null | grep '^hone/')
}

# 10. Run in the primary tree. Print each change this clone holds a claim on
# with no worktree. Only this clone's own claims live under refs/hone/claim/
# (status fetches the team's into refs/hone/remote-claim/), so the check
# never touches the network.
hy_stale_claims() {
    local c
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        [ -d ".worktrees/$c" ] && continue
        printf '%s\n' "$c"
    done < <(git for-each-ref --format='%(refname)' 'refs/hone/claim/' 2>/dev/null | sed 's|^refs/hone/claim/||')
}

# 7. Print "<file>\t<memory-dir>" for each project memory of project root $1.
# The harness keys its memory directory by the project's absolute path with
# "/" replaced by "-". That key is an undocumented harness detail, so the
# check FAILS OPEN: an absent directory yields nothing. It tries both the
# symlink-resolved and the as-given path.
hy_memory_files() {
    local root="$1" mem_root candidate mem_dir seen="" mem
    mem_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
    [ -d "$mem_root" ] || return 0
    for candidate in "$(cd "$root" 2>/dev/null && pwd -P)" "$root"; do
        [ -n "$candidate" ] || continue
        mem_dir="$mem_root/$(printf '%s' "$candidate" | tr '/' '-')/memory"
        [ -d "$mem_dir" ] || continue
        case "$seen" in *"|$mem_dir|"*) continue ;; esac
        seen="$seen|$mem_dir|"
        while IFS= read -r mem; do
            [ -n "$mem" ] || continue
            printf '%s\t%s\n' "$(basename "$mem")" "${mem_dir/#$HOME/\~}"
        done < <(grep -rlE '^[[:space:]]*type:[[:space:]]*project[[:space:]]*$' "$mem_dir" --include='*.md' 2>/dev/null | sort)
    done
}
