"""Pre-convert the paths people actually ask for.

A conversion on a 1-core VPS takes a second or two. Doing it once, ahead of
time, for the handful of formats that are actually requested turns that into a
static file served by Nginx.

This is a convenience, not a dependency: with the worker never run, every
endpoint behaves identically and the first request for a given conversion
simply pays for it.

    python3 warm_cache.py --top 20
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

PF_BIN = os.environ.get("PF_BIN", "pseudoforge")

# The formats a UPF is actually asked for. Anything refused is not listed --
# the core would refuse it again, and warming a refusal caches nothing.
TARGETS = {"upf": ["xml", "psp8"]}


def core(method: str, path: str, body: str | None = None):
    argv = [PF_BIN, "api", method, path] + ([body] if body else [])
    p = subprocess.run(argv, capture_output=True, text=True)
    try:
        return json.loads(p.stdout or "{}")
    except json.JSONDecodeError:
        return {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=20, help="how many files to warm")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    files = core("GET", "/api/native")
    if not isinstance(files, list):
        print("no native index; run: pseudoforge native index", file=sys.stderr)
        return 1

    done = failed = skipped = 0
    for entry in files[: args.top]:
        for target in TARGETS.get(entry.get("format", ""), []):
            body = json.dumps({"id": entry["id"], "to": target})
            if args.dry_run:
                print(f"would warm {entry['id']} -> {target}")
                skipped += 1
                continue
            import tempfile

            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
                fh.write(body)
                tmp = fh.name
            try:
                res = core("POST", "/api/convert", tmp)
            finally:
                os.unlink(tmp)
            if "error" in res:
                # A refusal is a correct answer, not a failure of the worker.
                print(f"{entry['id']} -> {target}: {res.get('error')}")
                failed += 1
            else:
                done += 1

    print(f"warmed {done}, {failed} not converted, {skipped} skipped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
