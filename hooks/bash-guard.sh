#!/bin/bash
# PreToolUse guard for Bash commands (Claude Code).
#
# Tamper resistance for hone's enforcement. The Write/Edit deny rules in
# settings.json stop the file tools. This hook closes the obvious SHELL routes
# around them and around the gate. The threat model is a friction-avoiding agent
# that takes an open path, not an adversary. So this hook is a DETERRENT, not a
# sandbox: multi-step obfuscation (write-a-script-then-run-it, `python -c`,
# base64) can still evade string matching. It deters and makes tampering
# attributable.
#
#   deny: unambiguous attempts to disable the gate or its markers
#   ask:  a mutating op aimed at a protected artifact (escalate to the human)
#
# The same .hone-off marker that disables the rest of hone disables this hook.

set -uo pipefail

# shellcheck source=hooks/common.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=hooks/messages.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/messages.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT" || exit 0
[ -f ".hone-off" ] && exit 0

# $1 = deny|ask, $2 = a template from messages.sh (already prefixed).
decision() { hone_pretool_decision "$1" "$2"; exit 0; }

# Sabotage tokens. Both scan paths share this one definition, so the two cannot
# drift. HARD_TOKENS always mean "disable the whole gate": sabotage on any path.
# MARKER_TOKENS are context-dependent. CREATING .hone-off disables hone, and
# HAND-WRITING a grant or proof sign-off bypasses the helpers that make the
# record readable. The constructs below deny both. Reading or removing one is
# legitimate, so a bare mention only escalates on the fail-closed backstop, and
# never auto-denies.
HARD_TOKENS='--no-verify|core\.hooksPath'
MARKER_TOKENS='\.hone-off|\.hone-(grant|proof)/'

INPUT=$(cat)
CMD=$(hone_extract_field "$INPUT" command)

if [ -z "$CMD" ]; then
    # Parsing failed. Fail closed: if the raw payload carries any gate-sabotage
    # token, escalate. Otherwise nothing is actionable, so allow.
    if echo "$INPUT" | grep -Eq "$HARD_TOKENS|$MARKER_TOKENS"; then
        decision ask "$(msg_bashguard_unparsed)"
    fi
    exit 0
fi

# 1. Unambiguous gate / marker sabotage → deny: a hard token, or a shell
# construct that CREATES .hone-off.
#
# Only CREATION counts. `echo` and `printf` used to match on a bare mention of
# the marker, so the guard denied a read-only existence check (`ls .../.hone-off
# || echo "no .hone-off marker present"`) as sabotage. The redirect rule below
# already catches every command that writes the marker, whichever program
# produces the text. So the two creation verbs that write no redirect (touch,
# install) are the whole list.
if echo "$CMD" | grep -Eq \
        -e "$HARD_TOKENS" \
        -e '(^|[^A-Za-z_])(HUSKY|LEFTHOOK|GIT_CONFIG[A-Z_]*)=' \
        -e '(touch|install)[^|;&]*\.hone-off' \
        -e '>[[:space:]]*[^|;&[:space:]]*\.hone-off'; then
    decision deny "$(msg_bashguard_sabotage)"
fi

# 1b. HAND-WRITING an authority grant or a proof sign-off → deny. The helpers
# (worktree.sh grant and attest) are the only route to these files, for the
# agent as much as for a person. They are what stamps the signer, binds a
# sign-off to the commit it proves, and refuses an empty or placeholder text.
# A raw write past them produces a file the gate may accept and no reader can
# trust. So every shell route to the file itself stays denied. The rule allows
# the helpers themselves.
# The mutating-op list is a superset of rule 2's below (creation verbs plus
# every mutator). So a token rule 2 treats as a write cannot pass here.
if echo "$CMD" | grep -Eq \
        -e '(touch|install|printf|echo|tee|cp|mv|mkdir|ln|sed -i|rm |truncate|dd|chmod|chattr)[^|;&]*\.hone-(grant|proof)/' \
        -e '>>?[[:space:]]*"?'"'"'?[^[:space:]|;&]*\.hone-(grant|proof)/'; then
    decision deny "$(msg_bashguard_signoff)"
fi

# 2. A mutating operation aimed at a protected artifact → ask. The committed
# policy files are protected too. Editing .hone-durable-paths,
# .hone-irreversible-paths, the .hone-proof-always marker, or the
# .hone-review-always list shrinks or widens the enforcement perimeter, which is
# the human's call. Deleting the marker is the cheapest way past the land proof
# gate, and deleting the list is the cheapest way past a review. So both
# escalate like the rest.
PROT='scripts/run-tests\.sh|scripts/typecheck\.sh|scripts/lint\.sh|scripts/proof\.sh|hooks/(guard|gate|nag|bash-guard|session-start|common|messages)\.sh|\.claude/settings(\.local)?\.json|\.hone-durable-paths|\.hone-(irreversible|consequential)-paths|\.hone-proof-always|\.hone-review-always'
# The two constructs need different shapes, so they get one branch each.
#
# A REDIRECT writes to the path that follows it, with nothing in between. So it
# binds tightly, the way rule 1b already writes it. One loose rule for both
# constructs read any '>' anywhere in the line as a write into any protected
# path later in the line. A quoted message is prose, and prose carries angle
# brackets: `attest <change> "ran PROOF_ROOT=<worktree> bash scripts/proof.sh"`
# escalated on its own text. That ask stopped two unattended runs for 16 and 48
# minutes, on the one helper the agent is meant to call by itself.
#
# A VERB takes a source and a target, so it keeps the loose gap.
if echo "$CMD" | grep -Eq \
        -e ">>?[[:space:]]*\"?'?[^[:space:]|;&]*(${PROT})" \
        -e "(tee|sed -i|cp |mv |install |ln -s|chmod|chattr|rm |truncate|dd of=)[^|;&]*(${PROT})"; then
    decision ask "$(msg_bashguard_protected)"
fi

# Rules 3 and 4 both apply to the primary tree alone. They need the tree the
# command WRITES IN, which is not the tree the hook stands in. The hook process
# starts in the directory the session started in, and it stays there for the
# whole session. The shell that runs the command does not. `cd "$WT"` moves that
# shell, and every later Bash call runs in the worktree while the hook still
# stands in the primary tree.
#
# The harness reports the shell's directory in the top-level `cwd` field of the
# hook input. Claude Code updates that field after each `cd`, and when Claude
# enters a worktree, while ${CLAUDE_PROJECT_DIR} and the hook's own cwd stay
# put. Reading it is the whole fix for the common misfire: the run loop cds into
# its worktree once (skills/run/SKILL.md step 1) and works there, so every
# formatter run and every package install after that cd read as primary-tree
# work. Rule 4 then told the agent to move work into a worktree it was already
# standing in.
#
# Fall back to the hook's own cwd when the field is absent or names no directory
# (an older harness, a hand-driven test).
SHELL_CWD=$(hone_extract_top_field "$INPUT" cwd)
[ -n "$SHELL_CWD" ] && [ -d "$SHELL_CWD" ] || SHELL_CWD="$PWD"

# A leading `cd <target>` moves the shell once more, inside the command itself,
# so it wins over the field above. A relative target resolves against the
# shell's directory, not the hook's.
#
# Fail closed on anything unclear, which keeps the escalation rather than
# dropping it. Unclear means more than one cd, a cd that is not first, or a
# target that is not a directory. A command that returns to the primary tree
# must never read as worktree work. Each case falls back to the shell's cwd.
#
# A subshell wraps the same idiom: `(cd <worktree> && <tool>)`. The `(` counts
# as a separator here, and the extractor accepts one before a leading cd.
# Without that, the wrapped form read as primary-tree work while the unwrapped
# form passed, and the hook told the agent to move work it had already moved.
TREE_DIR="$SHELL_CWD"
if [ "$(printf '%s\n' "$CMD" | grep -Eo '(^|[;&|(][[:space:]]*)cd[[:space:]]' | wc -l)" -eq 1 ]; then
    CD_TARGET=$(printf '%s' "$CMD" | sed -n \
        "s/^[[:space:]]*(\{0,1\}[[:space:]]*cd[[:space:]]\{1,\}\(\"[^\"]*\"\|'[^']*'\|[^[:space:];&|]\{1,\}\).*/\1/p")
    CD_TARGET=${CD_TARGET%\"}; CD_TARGET=${CD_TARGET#\"}
    CD_TARGET=${CD_TARGET%\'}; CD_TARGET=${CD_TARGET#\'}
    case "$CD_TARGET" in
        ''|/*) ;;
        *) CD_TARGET="$SHELL_CWD/$CD_TARGET" ;;
    esac
    [ -n "$CD_TARGET" ] && [ -d "$CD_TARGET" ] && TREE_DIR="$CD_TARGET"
fi

# git-dir == common-dir ⇔ TREE_DIR is the primary tree, not a linked worktree
# (whose git-dir sits under .git/worktrees/). So neither rule fires for work
# aimed at a worktree, which is where both operations are safe and belong.
IN_PRIMARY_TREE=0
[ "$(git -C "$TREE_DIR" rev-parse --git-dir 2>/dev/null)" \
  = "$(git -C "$TREE_DIR" rev-parse --git-common-dir 2>/dev/null)" ] \
    && IN_PRIMARY_TREE=1

# 3. A HEAD-moving git op in the PRIMARY tree → ask. The primary tree is a merge
# target kept on the trunk. Landing goes through `worktree.sh land`, which
# serializes the merge under a lock. Moving the shared HEAD by hand (a branch
# switch, a stash, a hard reset) races every other session that shares this
# tree. That is the exact collision this rule guards against. Investigation
# belongs in a throwaway `git worktree add --detach`. `git checkout` has its own rule below, because
# one of its forms restores files and moves no HEAD.
if [ "$IN_PRIMARY_TREE" -eq 1 ] \
   && echo "$CMD" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+(switch([[:space:]]|$)|reset[^|;&]*--(hard|merge|keep))'; then
    decision ask "$(msg_bashguard_head_move)"
fi

# 3a. `git stash` reads in two of its forms and mutates in every other. `list`
# and `show` only read the stash, and the rule used to escalate them with the
# rest. That ask stopped unattended runs on a read, and one agent paged the
# operator to confirm a `git stash list`. So the two read verbs pass, judged
# per segment the way rule 3b judges checkout. Everything else still asks:
# `pop`, `drop`, `clear`, a bare `git stash`, a flags-first form like
# `git stash -u`, and any subcommand this rule does not know. Unknown fails
# closed, so a new stash verb escalates until someone reads it.
if [ "$IN_PRIMARY_TREE" -eq 1 ]; then
    while IFS= read -r seg; do
        printf '%s\n' "$seg" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+stash([[:space:]]|$)' || continue
        printf '%s\n' "$seg" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+stash[[:space:]]+(list|show)([[:space:]]|$)' && continue
        decision ask "$(msg_bashguard_head_move)"
    done < <(printf '%s\n' "$CMD" | tr '|;&' '\n\n\n')
fi

# 3b. `git checkout` moves HEAD in one form and restores files in another, so it
# needs the extra check that rule 3 does not. `git checkout -- <paths>` and `git
# checkout <ref> -- <paths>` write files and leave HEAD where it is, which is
# the sanctioned way to undo a bad edit in the primary tree. Flagging them sent
# the operator to a scratch worktree to restore two files.
#
# The `--` pathspec separator is the signal. The rule reads it per command
# segment, so a restore later in the line cannot excuse a real HEAD move
# earlier in it.
# Residual false positive: `git checkout <file>` without the separator is
# indistinguishable from `git checkout <branch>` here, so it still asks.
if [ "$IN_PRIMARY_TREE" -eq 1 ]; then
    while IFS= read -r seg; do
        printf '%s\n' "$seg" | grep -Eq '(^|[^A-Za-z_])git[[:space:]]+checkout([[:space:]]|$)' || continue
        printf '%s\n' "$seg" | grep -Eq '[[:space:]]--([[:space:]]|$)' && continue
        decision ask "$(msg_bashguard_head_move)"
    done < <(printf '%s\n' "$CMD" | tr '|;&' '\n\n\n')
fi

# 4. A tool that writes its OWN files, run in the PRIMARY tree → ask. This is
# the preventive half of the primary-tree rule for the shell route, and
# dirty-guard.sh (PostToolUse) is the half that catches what this list misses.
# Rule 2 above cannot see these. A package manager rewrites package.json from
# inside its own process, so the command text carries neither a write construct
# nor the path.
#
# This is an allow-list of names, so it DRIFTS by construction. A new package
# manager, a new migrate subcommand, or a wrapper script that calls one is a
# hole until someone adds it here. That is why it only escalates, and why
# dirty-guard checks the effect instead. Keep the boundary loose: a writer
# anywhere in the command, so `bunx biome migrate` and `sudo npm install` both
# match. Accept that prose quoting one of these names also escalates. An
# ask costs one keystroke, and a missed dependency sweep costs a bad commit.
#
# A BARE SYNC INSTALL is the exception: `bun install`, `npm ci`, `poetry
# install`, with flags only, installs what the lockfile already says and writes
# no durable file. It is also the sanctioned next step after a land that changed
# the lockfile, and this rule used to escalate it. dirty-guard sees whatever
# such a command leaves dirty. That check catches any write to a durable path,
# so a preventive ask here gains nothing.
#
# The verb's argument separates the two cases. End of command or flag tokens
# only means sync. A non-flag argument names a package, which mutates the
# manifest. So `npm install lodash`, `bun add x`, and `poetry add y` still
# escalate, as does every add/remove/update/upgrade/link verb below.
NAMED_ARG='([[:space:]]+-[^[:space:];&|]*)*[[:space:]]+[^-[:space:];&|]'
SELF_WRITERS='(npm|pnpm|yarn|bun|deno)[[:space:]]+(add|remove|rm|uninstall|update|upgrade|up|link|pkg)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(npm|pnpm|yarn|bun|deno)[[:space:]]+(install|i|ci)'"$NAMED_ARG"
SELF_WRITERS="$SELF_WRITERS"'|(pip|pip3|uv|poetry|cargo|bundle|gem|mix|composer)[[:space:]]+(add|remove|uninstall|lock|update|upgrade|require|fmt)([[:space:]]|$)'
SELF_WRITERS="$SELF_WRITERS"'|(pip|pip3|uv|poetry|cargo|bundle|gem|mix|composer)[[:space:]]+(install|sync|deps\.get)'"$NAMED_ARG"
SELF_WRITERS="$SELF_WRITERS"'|go[[:space:]]+(get|mod)([[:space:]]|$)'
if [ "$IN_PRIMARY_TREE" -eq 1 ] && echo "$CMD" | grep -Eq "(^|[^A-Za-z0-9_.-])(${SELF_WRITERS})"; then
    decision ask "$(msg_bashguard_self_writer)"
fi

# 4b. A FORMATTER in write mode, in the PRIMARY tree. A formatter differs from
# the package managers above in one way that matters: its command names the
# paths it writes. So the hook can apply the same perimeter the file tools
# already apply. `Write` to `.plans/<change>.md` is allowed in the primary tree,
# because the Plan is the one artifact written outside the loop, and the lint
# gate wants that file formatted before its commit. The formatter run that does
# the formatting is the same write through the shell route. Escalating it asked
# the operator to approve a step the workflow itself requires, fifteen times in
# one week.
#
# So a write-mode formatter passes only when it is SCOPED: at least one path
# argument, and every argument a relative, non-durable path. Everything else
# still asks. That includes a bare `dprint fmt` (it formats docs/), any durable
# path, any flag beyond the write-mode flags themselves (a `--config` swap can
# repoint the tool), a glob in a directory part, and every token this walk does
# not recognise. Fail closed keeps the ask; the exemption has to be earned.
#
# The ask prints msg_bashguard_formatter, not rule 4's message. Scoping the run
# is the remedy here, and a package manager has no such remedy. The shared
# message named the worktree alone, so a bare `dprint fmt` in the primary tree
# sent the operator to a worktree while the one-word fix went unmentioned.
#
# Residual hole: the walk reads a path token as written, and hone_is_durable
# reads a project-relative path. So a formatter run from a SUBDIRECTORY of the
# primary tree judges `notes.md` and not `docs/notes.md`, and the exemption is
# wider there than the file tools' perimeter. dirty-guard.sh reads the effect,
# so it still blocks that write.
FMT_WRITERS='(biome|eslint|prettier|dprint|ruff|black|isort|rustfmt|gofmt|jscodeshift|codemod)[^|;&]*(migrate|--write|--fix|--apply|[[:space:]]-w([[:space:]]|$)|[[:space:]]fmt([[:space:]]|$)|[[:space:]]format([[:space:]]|$))'

# True when segment $1 scopes its formatter to non-durable relative paths.
# A subshell body: `set -f` must not leak, and the tokens must be judged as
# written, not as whatever they happen to glob to in the hook's cwd.
hone_fmt_scoped() (
    set -f
    local tok dir n=0
    for tok in $1; do
        tok=${tok%\"}; tok=${tok#\"}; tok=${tok%\'}; tok=${tok#\'}
        while [ "${tok#./}" != "$tok" ]; do tok=${tok#./}; done
        case "$tok" in
            ''|bunx|npx|sudo|--bun|deno|run|exec|dlx) continue ;;
            biome|eslint|prettier|dprint|ruff|black|isort|rustfmt|gofmt|jscodeshift|codemod) continue ;;
            fmt|format|check|lint|migrate) continue ;;
            --write|--fix|--apply|-w) continue ;;
            [0-9]">"*|">"*|"<"*) continue ;;
            -*) return 1 ;;
            *..*|*'$'*|*'`'*|/*|"~"*|.) return 1 ;;
            */*|*.*)
                case "$tok" in
                    */*) dir=${tok%/*} ;;
                    *) dir='' ;;
                esac
                case "$tok" in
                    *[\*\?\[]*)
                        # A glob is judged by its literal directory part. A glob
                        # in the directory, or a rootless glob, stays an ask.
                        [ -n "$dir" ] || return 1
                        case "$dir" in *[\*\?\[]*) return 1 ;; esac
                        hone_is_durable "$dir/x" && return 1 ;;
                    *)
                        hone_is_durable "$tok" && return 1 ;;
                esac
                n=$((n+1)) ;;
            *) return 1 ;;
        esac
    done
    [ "$n" -ge 1 ]
)

if [ "$IN_PRIMARY_TREE" -eq 1 ]; then
    while IFS= read -r seg; do
        printf '%s\n' "$seg" | grep -Eq "(^|[^A-Za-z0-9_.-])(${FMT_WRITERS})" || continue
        hone_fmt_scoped "$seg" && continue
        decision ask "$(msg_bashguard_formatter)"
    done < <(printf '%s\n' "$CMD" | tr '|;&' '\n\n\n')
fi

exit 0
