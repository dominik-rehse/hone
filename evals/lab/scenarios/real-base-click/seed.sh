# A real base in place of a fixture of a hundred lines: pallets/click at the
# tag 8.5.0, 12,674 lines of source under src/click/ and 15,800 lines of tests,
# BSD-3-Clause. The commit below is the pin. Nothing of it is committed into
# this repository: the seed fetches it.
#
# The Plan asks for one new decorator, `click.config_option`, which reads the
# default values of a command out of a JSON file. Two things the base already
# has make the difference, and neither is in the Plan:
#
#   Context.default_map is the map that click itself consults between the
#   environment and a parameter's declared default (Parameter.consume_value).
#   docs/commands.md documents it, nesting and all. A change that uses it gets
#   the order of precedence, the type cast, and the help text for free. A
#   change that places the values itself must get all three right by hand.
#
#   utils.get_app_dir names the per-user configuration directory of an
#   application. A hand-written path joins the home directory and `.config`,
#   and so it ignores XDG_CONFIG_HOME.
#
# check.sh measures both, and its hidden proof decides `correct`. The run never
# sees that proof.
#
# The fetch: a bare mirror under /var/tmp holds the one commit, so a repeated
# run fetches nothing. With no mirror and no network the seed stops with the
# reason, which the harness reports as indeterminate and never as a result
# about hone. The wheels go to a cache under the same directory, which
# pyproject.toml names, so every worktree of a run resolves offline.
#
# This scenario runs by name only (the `by-name` file beside this one).

PIN=8b19813f2bfca99f1018a587a8cf54fc959f2e5d   # pallets/click, tag 8.5.0
CACHE="${LAB_BASE_CACHE:-/var/tmp/hone-lab-bases}"
MIRROR="$CACHE/click.git"

command -v uv >/dev/null || { echo "the real-base-click fixture needs uv on PATH" >&2; exit 1; }
command -v git >/dev/null || { echo "the real-base-click fixture needs git on PATH" >&2; exit 1; }

mkdir -p "$CACHE" || { echo "cannot create the base cache $CACHE" >&2; exit 1; }
fetch_base() {
    git -C "$MIRROR" cat-file -e "$PIN^{commit}" 2>/dev/null && return 0
    [ -d "$MIRROR" ] || git init -q --bare "$MIRROR" || return 1
    git -C "$MIRROR" fetch -q --depth 1 https://github.com/pallets/click "$PIN"
}
if command -v flock >/dev/null; then
    # Two scenarios of one pass may seed at the same time.
    ( flock 9 || exit 1; fetch_base ) 9>"$CACHE/click.lock" || fetched=no
else
    fetch_base || fetched=no
fi
[ "${fetched:-yes}" = yes ] || {
    echo "no copy of pallets/click $PIN in $MIRROR, and the fetch failed." >&2
    echo "This scenario needs the network once. After that it seeds from the cache." >&2
    exit 1
}
git -C "$MIRROR" archive "$PIN" | tar -x || { echo "could not unpack the pinned base" >&2; exit 1; }

# The base seed installed the Node adapter for its own package.json. Drop both,
# and let hone's setup.sh give this fixture what a real Python consumer gets.
rm -f package.json scripts/run-tests.sh
# uv resolves every group of a pallets project by default, which pulls a type
# checker and a linter that nothing here runs. The tests group is pytest alone.
# The cache directory is shared, so a worktree of a run needs no network.
sed -i 's/^default-groups = .*/default-groups = ["tests"]/' pyproject.toml
sed -i '/^default-groups = \["tests"\]$/a cache-dir = "'"$CACHE"'/uv-cache"' pyproject.toml
grep -q '^cache-dir = ' pyproject.toml \
    || { echo "the base's pyproject.toml has no [tool.uv] block to point at the cache" >&2; exit 1; }

CLAUDE_PROJECT_DIR="$PWD" bash "$LAB_PLUGIN/scripts/setup.sh" >/dev/null 2>&1 \
    || { echo "hone's setup.sh failed on the real-base-click fixture" >&2; exit 1; }
grep -q 'uv run pytest' scripts/run-tests.sh \
    || { echo "setup.sh installed no Python test adapter" >&2; exit 1; }
# A tracked cache leaves the primary tree dirty after every suite run, which
# `revertible` reads as a fail. The base ignores .venv/ and __pycache__/ itself.
for entry in '.venv/' '__pycache__/' '.pytest_cache/'; do
    grep -qxF "$entry" .gitignore || printf '%s\n' "$entry" >> .gitignore
done

mkdir -p docs/notes .plans/click
cat > docs/notes/click.md <<'MD'
# click

Governs: `src/click/`

Map: `core.py` holds the context, the command, the group, and the parameter.
`decorators.py` holds what a user puts on a function. `types.py` turns a string
from the command line into a value. `utils.py` and `formatting.py` hold the
helpers that the rest of the package shares.

Invariant: every public name of the package is re-exported from
`src/click/__init__.py`, one name per line.
MD

cat > .plans/click/config-option.md <<'PLAN'
# Plan: click/config-option

## What
A parameter of a command takes its value from the command line, from an
environment variable, or from the default that the option declares. Nothing
reads such values out of a file. Add `config_option` to
`src/click/decorators.py` and export it as `click.config_option`. Its signature
is `config_option(*param_decls, app_name, filename="config.json", **kwargs)`.
It declares one eager option, `--config` when the caller names none, which
takes the path of a JSON file and never reaches the command's own callback.
The object in that file holds one entry per parameter name of the command. An
entry whose value is itself an object holds the parameters of the subcommand of
that name, to any depth. A value that the user gives on the command line wins
over a value from the file. When the caller gives no `--config`, the decorator
looks for `filename` in the per-user configuration directory of `app_name`,
which is the directory this package already knows for an application's own
files. With no file there, the command behaves as it does today. A `--config`
path that names no file ends the command with the message this package already
writes for a path that does not exist. A file that holds no JSON object ends
the command with a usage error that names the path.

## Why
An application built on this package has no way to ship or keep settings. Its
author writes the same loader again each time, and each one places the values
somewhere else in the order of precedence. Two of the four applications in our
own house read a file before the parser runs and lose the environment variable.

## How I'll know it works
Take a group `cli` with the subcommand `serve`, which takes `--port`, an
integer whose declared default is 8000. With a file that holds
`{"serve": {"port": 5000}}`, `cli --config <path> serve` uses 5000, and
`cli --config <path> serve --port 1234` uses 1234. A `--config` path that names
no file ends with exit code 2. A file whose text is `{not json` ends with exit
code 2 and a message that names the path. With no file at the per-user place,
`cli serve` still uses 8000. Tests under `tests/` pin all of it, and
`scripts/run-tests.sh --all` stays green.

## Notes for the loop
- Touches `src/click/decorators.py`, `src/click/__init__.py`, and `tests/`.
  Independent of in-flight work.
- Not a critical path.
PLAN

# Resolve the test dependency once, so uv.lock and the shared wheel cache are
# part of the seed and every later call of the adapter resolves from disk.
uv sync --quiet >/dev/null 2>&1 \
    || { echo "uv sync could not build the fixture's environment" >&2; exit 1; }
bash scripts/run-tests.sh --all >/dev/null 2>&1 \
    || { echo "the seeded suite is red, so no run of this scenario would mean anything" >&2; exit 1; }
