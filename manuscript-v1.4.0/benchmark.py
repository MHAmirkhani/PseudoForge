#!/usr/bin/env python3
"""Repeat the ten-element generation case with an external wall clock."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ELEMENTS = "Si,Fe,Cu,Al,C,O,Ti,Ni,N,H"
ROOT = Path(__file__).resolve().parent.parent


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--ld1", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=3)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    binary = args.ld1.resolve(strict=True)
    repo = args.repo.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    common = [
        str(repo / "pseudoforge"), "generate", "-e", ELEMENTS, "--engine", "ld1",
        "-p", "psl-high", "-t", "paw", "-x", "pbe", "-r", "scalar",
        "--source", "local", "--formats", "upf", "--no-test",
    ]
    hashes = []
    rows = []
    with tempfile.TemporaryDirectory(prefix="pf-bench-") as temp:
        work = Path(temp)
        config = work / "pseudoforge.rc"
        config.touch()
        env = dict(os.environ, LD1_BIN=str(binary), OMP_NUM_THREADS="1",
                   OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1",
                   PF_AUTO_INSTALL_LD1="no", PF_RC=str(config), LC_ALL="C")
        env.pop("OMPI_MCA_btl", None)
        for trial in range(1, args.repeats + 1):
            for workers in (1, 2, 4, 8):
                label = f"j{workers}-r{trial}"
                target = work / label
                command = common + ["-j", str(workers), "-o", str(target)]
                with (output / f"{label}.log").open("w") as log:
                    start = time.perf_counter()
                    process = subprocess.run(command, cwd=work, env=env, stdin=subprocess.DEVNULL,
                                             stdout=log, stderr=subprocess.STDOUT, timeout=240)
                    seconds = time.perf_counter() - start
                process.check_returncode()
                files = sorted((target / "pseudos").glob("*.UPF"))
                if len(files) != 10:
                    raise RuntimeError(f"{label} produced {len(files)} UPFs")
                hashes.append({f.name: sha256(f) for f in files})
                rows.append([trial, workers, f"{seconds:.3f}", len(files)])
                print(label, f"{seconds:.3f} s", flush=True)
                if trial == 1 and workers == 8:
                    (output / "sample-provenance.txt").write_text(
                        (target / "PROVENANCE.txt").read_text().replace(str(work), "<work>"))
    with (output / "timings.csv").open("w", newline="") as table:
        writer = csv.writer(table)
        writer.writerow(["trial", "workers", "seconds", "upfs"])
        writer.writerows(rows)
    (output / "hashes.json").write_text(json.dumps(
        {f"j{row[1]}-r{row[0]}": digest for row, digest in zip(rows, hashes)}, indent=2) + "\n")
    (output / "benchmark-environment.txt").write_text(
        subprocess.check_output(["lscpu"], text=True).split("Flags:")[0]
        + f"OS: {os.uname().sysname} {os.uname().release}\n"
        + f"ld1.x SHA-256: {sha256(binary)}\n"
        + f"PseudoForge commit: {subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True)}"
        + f"UPF SHA-256 matched in all runs: {all(digest == hashes[0] for digest in hashes)}\n"
    )


if __name__ == "__main__":
    main()
