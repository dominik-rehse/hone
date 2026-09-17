# Working in the hone repository

These are the standing instructions for a Claude Code session in this repo.
They are not shipped, and they are the only place such instructions live.

## No memories

Do not write to the harness memory store for this repo. Every fact worth
keeping goes into the repo, so it travels with a clone and a reviewer can
read it. A standing instruction goes in this directory. A release step goes
in `releasing.md` beside this file. A measurement or an audit goes under
`docs/spikes/` as a dated note. A rationale goes in `docs/model.md`. If a
fact fits none of those, ask where it belongs instead of storing it outside
the repo.

## How to write to the maintainer

Write plain English. hone's own docs and prompts use a dense, aphoristic
voice on purpose, and that voice is not a model for conversation. Avoid
these: em-dash asides, bolded epigrams, "the answer is not X, it is Y"
constructions, and rule-of-three lists. Avoid coined terms in italics and
headers that read like essay titles. Short declarative sentences. Say the
thing, then the reason.

Answer in the terminal. Do not publish an HTML page unless the content
needs a visual: a chart, a diagram, an interactive tool. A findings report,
an audit, a review, or a plan is terminal output, however long. If a page
might help, offer it in one line.

## The plugin runs in this repo

This repository enables hone on itself, so its hooks read every shell
command and every commit message here. The bash-guard denies a command
that names a sabotage token, whatever its intent. The tokens are the flag
that skips git hooks, the config key that redirects them, and a write to
the off marker. To test such a command, write it to a script in the
scratchpad and run the script. Keep
commit messages free of the literal tokens too. Write "the no-verify flag"
and "the hooks-path key" instead.
