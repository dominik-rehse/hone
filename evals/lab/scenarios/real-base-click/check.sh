# The right end state of the real base. The head of seed.sh says what the base
# is and what the change hides.
#
# The proof below is hidden: it is in no file of the fixture, and the run never
# reads it. It builds a small CLI on the landed package and drives it with the
# package's own test runner. Eight tokens come back. Four of them the Plan
# states. The other four are what the wider code decides, and only a reader of
# it gets them right:
#
#   an environment variable beats a value from the file (Parameter.consume_value)
#   a string in the file is cast to the parameter's type, as an environment
#     value is
#   `--help` shows what the command would really use, not the declared default
#   the file of one call does not stay behind for the next call in the process
#
# Two measures follow, and neither decides the verdict:
#
#   dup      `reused` when the value arrived through click's own default map,
#            which ParameterSource names. `copied` when the change placed the
#            value some other way, which is a second copy of a mechanism the
#            base already has. scb-check does not see this one: the two end
#            states we built by hand both read clone_loc 452, because the
#            duplicate is of a mechanism and not of any lines
#            (docs/spikes/2026-09-20-real-base-scenario.md).
#   appdir   `reused` when the per-user directory came from the base's own
#            helper, which reads XDG_CONFIG_HOME. `own` when the change joined
#            the home directory and `.config` itself.
#
# Both arms are measured alike. On the bare arm the checks on an artifact of
# hone fail by construction, so read `correct` and `dup` there, not the verdict.

landed click/config-option
suite_green
plan_deleted click/config-option
worktree_removed
revertible
commits_conform
review_ran
unchanged scripts/run-tests.sh pyproject.toml uv.lock
diff_confined '^(src/click/|tests/|docs/|CHANGES\.md|\.plans/)'

# The package has no runtime dependency, so the proof needs the interpreter and
# nothing else. A machine that cannot run it must not record a number.
if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    echo "  BROKEN the proof needs python3 3.10 or newer"
    exit 2
fi

probe=$(mktemp "${TMPDIR:-/tmp}/hone-lab-probe.XXXXXX")
cat > "$probe" <<'PY'
import json
import os
import tempfile

import click
from click.testing import CliRunner


def build():
    @click.group()
    @click.config_option(app_name="labcli")
    def cli():
        pass

    @cli.command()
    @click.option(
        "--port", type=int, default=8000, show_default=True, envvar="LABCLI_PORT"
    )
    @click.pass_context
    def serve(ctx, port):
        click.echo(f"{port} {ctx.get_parameter_source('port').name}")

    return cli


def write(path, data):
    with open(path, "w", encoding="utf-8") as f:
        f.write(data if isinstance(data, str) else json.dumps(data))
    return path


def main():
    try:
        cli = build()
    except Exception as e:  # the decorator is absent, or its signature differs
        print(f"PROOF build-failed {type(e).__name__}: {e}")
        print("SOURCE none")
        print("APPDIR none")
        return

    runner = CliRunner()
    tmp = tempfile.mkdtemp()
    empty = os.path.join(tmp, "empty")
    os.makedirs(os.path.join(empty, "home"))
    os.makedirs(os.path.join(empty, "xdg"))
    # Every call runs with an empty home, so nothing of the machine reaches the
    # CLI. The app-dir probe at the end is the one exception.
    base = {
        "HOME": os.path.join(empty, "home"),
        "XDG_CONFIG_HOME": os.path.join(empty, "xdg"),
    }

    def run(args, **env):
        return runner.invoke(cli, args, env={**base, **env})

    def port_of(result):
        parts = result.output.split()
        if result.exit_code != 0 or not parts:
            return f"exit{result.exit_code}"
        return parts[0]

    cfg = write(os.path.join(tmp, "config.json"), {"serve": {"port": 5000}})
    as_text = write(os.path.join(tmp, "as-text.json"), {"serve": {"port": "5000"}})
    broken = write(os.path.join(tmp, "broken.json"), "{not json")

    out = []
    # The Plan's own proof: the file gives the subcommand its default, and the
    # command line still wins.
    out.append(port_of(run(["--config", cfg, "serve"])))
    out.append(port_of(run(["--config", cfg, "serve", "--port", "1234"])))
    # What the wider code decides.
    out.append(port_of(run(["--config", cfg, "serve"], LABCLI_PORT="7000")))
    out.append(port_of(run(["--config", as_text, "serve"])))
    result = run(["--config", cfg, "serve", "--help"])
    out.append("5000" if "5000" in result.output else "no-default")
    # The two errors the Plan states.
    out.append(f"exit{run(['--config', os.path.join(tmp, 'absent.json'), 'serve']).exit_code}")
    out.append(f"exit{run(['--config', broken, 'serve']).exit_code}")
    # With no file anywhere, the declared default stands, in this call as in
    # the first one.
    out.append(port_of(run(["serve"])))
    print("PROOF " + " ".join(out))

    result = run(["--config", cfg, "serve"])
    parts = result.output.split()
    print("SOURCE " + (parts[1] if result.exit_code == 0 and len(parts) > 1 else "none"))

    xdg = os.path.join(tmp, "xdg-home")
    home = os.path.join(tmp, "plain-home")
    os.makedirs(os.path.join(xdg, "labcli"), exist_ok=True)
    os.makedirs(os.path.join(home, ".config", "labcli"), exist_ok=True)
    write(os.path.join(xdg, "labcli", "config.json"), {"serve": {"port": 4242}})
    write(os.path.join(home, ".config", "labcli", "config.json"), {"serve": {"port": 3131}})
    print("APPDIR " + port_of(run(["serve"], HOME=home, XDG_CONFIG_HOME=xdg)))


main()
PY
out=$(PYTHONPATH=src python3 -W ignore "$probe" 2>&1)
rm -f "$probe"
proof=$(printf '%s\n' "$out" | sed -n 's/^PROOF //p')
[ "$proof" = '5000 1234 7000 5000 5000 exit2 exit2 8000' ] && correct=yes || correct=no
measure correct "$correct"
[ "$correct" = yes ] && ok "the hidden proof holds on main" \
    || bad "the hidden proof does not hold on main: ${proof:-no PROOF line, last output: $(printf '%s\n' "$out" | tail -1)}"

case "$(printf '%s\n' "$out" | sed -n 's/^SOURCE //p')" in
    DEFAULT_MAP) dup=reused ;;
    none) dup=none ;;
    *) dup=copied ;;
esac
measure dup "$dup"

case "$(printf '%s\n' "$out" | sed -n 's/^APPDIR //p')" in
    4242) appdir=reused ;;
    3131) appdir=own ;;
    *) appdir=none ;;
esac
measure appdir "$appdir"

# Where the run said it stood. It only measures.
progress_lines
