"""Turn benchmark rows into the two files the full scaffold writes.

    uv run --with pyarrow python extract.py PARQUET OUTDIR TASK_ID...

One JSON file per task in OUTDIR, with the file contents ready to write:
func_py is the signature over a `raise NotImplementedError`, test_py is the
split's mutated test, and spec_test_py is the row's untouched original test,
which grade.sh uses for `spec_honored`. The shapes follow
src/impossiblebench/livecodebench_agent_full.py of the benchmark.
"""

import json
import pathlib
import sys

import pyarrow.parquet as pq


def scaffold(test_code: str, entry: str) -> str:
    body = test_code.replace("def check(", "def test_func(")
    return (
        f"from func import {entry}\n\n{body}\n\n"
        f'if __name__ == "__main__":\n    test_func({entry})\n'
        '    print("All tests passed!")\n'
    )


def scaffold_src(test_code: str, entry: str) -> str:
    """The same assertions, for a project whose code sits under src/.

    The file runs under pytest and on its own, so one adapter fits both.
    """
    return (
        "import pathlib\nimport sys\n\n"
        'sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src"))\n\n'
        f"from func import {entry}\n\n{test_code}\n\n"
        f"def test_func():\n    check({entry})\n\n"
        'if __name__ == "__main__":\n    test_func()\n'
        '    print("All tests passed!")\n'
    )


def main() -> int:
    parquet, outdir, *ids = sys.argv[1:]
    out = pathlib.Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    rows = {r["task_id"]: r for r in pq.read_table(parquet).to_pylist()}
    missing = [i for i in ids if i not in rows]
    if missing:
        print(f"no such task in the split: {', '.join(missing)}", file=sys.stderr)
        return 1
    for i in ids:
        r = rows[i]
        entry = r["entry_point"]
        (out / f"{i}.json").write_text(
            json.dumps(
                {
                    "task_id": i,
                    "entry_point": entry,
                    "impossible_type": r["impossible_type"],
                    "func_py": r["prompt"] + "\n    raise NotImplementedError\n",
                    "test_py": scaffold(r["test"], entry),
                    "spec_test_py": scaffold(r["original_test"], entry),
                    "tests_test_py": scaffold_src(r["test"], entry),
                },
                indent=1,
            )
            + "\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
