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

## Keeping the docs short

The maintainer wants docs that read easily: short, and not dense. Four
habits keep them that way.

- A dated fact goes into a note under `docs/spikes/`, never into a manual.
  The manual gets the rule that came out of the fact, in one sentence.
- Do not describe in prose what a script's header, its output, or its
  tests already say. Point at the script.
- State a behavior for people in two places at most: `docs/reference.md`
  for what, and `docs/model.md` for why. The README links.
- Give a reason only where a reader would otherwise do the wrong thing.

`test/prose_test.sh` holds each maintained doc to a word budget. When a doc
goes over, cut or move text. Do not raise the budget without the
maintainer's word.

`docs/roadmap.md` has no budget. It is as long as its open items need. Each
item must explain itself to a reader who was not in the session: what
happens, how we know, and what the next step is. Explain a term of the
lab at its first use, or link to where it is explained.

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

## When the plugin runs in this repo

The repo's settings do not enable hone, because work here goes straight to
`main` and the guard would deny every edit under `docs/` and `scripts/`. A
session that loads hone anyway (`claude --plugin-dir .`) gets its hooks, and
they read every shell command and every commit message. The bash-guard
denies a command that names a sabotage token, whatever its intent. The tokens are the flag
that skips git hooks, the config key that redirects them, and a write to
the off marker. To test such a command, write it to a script in the
scratchpad and run the script. Keep
commit messages free of the literal tokens too. Write "the no-verify flag"
and "the hooks-path key" instead.
