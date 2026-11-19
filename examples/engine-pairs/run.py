#!/usr/bin/env python3
"""Run matched native-generation trials and retain outputs, diagnostics and cost."""
import argparse
from bisect import bisect_right
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import pf_design as design

# Each arm keeps the physical starting profile and output representation fixed.
# GTH's baseline is a real fit with the same iteration limit and atomic input.
ARMS = {
    "ld1": ("Si", "pbe", "scalar", "paw", "psl-high", "upf", (), (
        ("s-radius", "--channel-rc", "s:1.60:1.90"),
        ("smaller", "--rcut-scale", "0.98"),
    )),
    "oncvpsp": ("Si", "pbe", "scalar", "nc", "sg15", "upf", (), (
        ("s-qcut", "--engine-option", "qcut.s=5.12"),
        ("larger", "--rcut-scale", "1.03"),
    )),
    "uspp": ("Si", "pbe", "scalar", "us", "gbrv", "upf", (), (
        ("smaller", "--rcut-scale", "0.99"),
        ("larger", "--rcut-scale", "1.01"),
    )),
    "fhi98pp": ("Si", "pw", "scalar", "nc", "fhi", "cpi", (), (
        ("r18", "--channel-rc", "s:1.8", "--channel-rc", "p:1.8", "--channel-rc", "d:1.8"),
        ("r19", "--channel-rc", "s:1.9", "--channel-rc", "p:1.9", "--channel-rc", "d:1.9"),
    )),
    "opium": ("Si", "pbe", "scalar", "nc", "opium", "upf", (), (
        ("sp19", "--channel-rc", "s:1.9", "--channel-rc", "p:1.9"),
        ("sp20", "--channel-rc", "s:2.0", "--channel-rc", "p:2.0"),
    )),
    "gth": ("Si", "pbe", "scalar", "nc", "cp2k-gth", "gth", ("--refit", "--refit-cycles", "80"), (
        ("eigenweight", "--engine-option", "fit.eigenvalue_weight=1.1"),
        ("chargeweight", "--engine-option", "fit.charge_weight=1.1"),
    )),
    "atompaw": ("Si", "pbe", "scalar", "paw", "atompaw", "upf", (), (
        ("smaller", "--rcut-scale", "0.98"),
        ("larger", "--rcut-scale", "1.02"),
    )),
    "ape": ("Si", "pbe", "scalar", "nc", "pseudoforge-auto", "upf", (), (
        ("local-s", "--lloc", "0"),
        ("larger", "--rcut-scale", "1.02"),
    )),
    "adpack": ("He", "pz", "full", "nc", "adpack", "openmx", (), (
        ("grid6000", "--engine-option", "grid.num=6000"),
        ("grid14000", "--engine-option", "grid.num=14000"),
    )),
}


def fhi_scattering(project, element):
    directory = project / "tests" / f"{element}.fhi"
    if not (directory / "pslp.out").is_file():
        return {}
    verdict = (project / "tests/transferability.tsv").read_text()
    if "reported no ghost states" not in verdict:
        return {}
    result = {}
    for file in sorted(directory.glob("fort.7[0-4]")):
        channel = file.name[-1]
        reference = [tuple(map(float, row.split())) for row in
                     (directory / f"fort.6{channel}").read_text().splitlines() if row.strip()]
        energies = [energy for energy, _ in reference]
        differences = []
        for row in file.read_text().splitlines():
            if not row.strip():
                continue
            energy, derivative = map(float, row.split())
            index = bisect_right(energies, energy)
            if not -0.5 <= energy <= 0.5 or not 0 < index < len(reference):
                continue
            x0, y0 = reference[index - 1]
            x1, y1 = reference[index]
            phase0 = math.atan(y0)
            phase = phase0 + math.remainder(math.atan(y1) - phase0, math.pi) * (energy - x0) / (x1 - x0)
            differences.append(math.remainder(math.atan(derivative) - phase, math.pi))
        if differences:
            result[channel] = {"samples": len(differences),
                               "rms_radians": math.sqrt(statistics.mean(value * value for value in differences))}
    return {"phase_comparison": {"energy_window_Ha": [-0.5, 0.5], "channels": result}}


def native_diagnostics(engine, project, element):
    if engine == "fhi98pp":
        return fhi_scattering(project, element)
    if engine == "adpack":
        file = project / "logs" / f"{element}.log"
        if not file.is_file():
            return {}
        log = file.read_text(errors="replace")
        values = re.findall(r"I0, dif of log deris for all electrons\s*=\s*(" + design.NUMBER + ")", log)
        return {"max_integrated_logderivative_error": max(float(value.replace("D", "E").replace("d", "e"))
                                                           for value in values) if values else None,
                "channel_count": len(values),
                "logderivative_nonconvergence_count": log.count("in LogDeriF.c"),
                "scope": "same-atom integrated native diagnostic over the input energy grid"}
    return {}


def run_arm(output, engine, timeout, env):
    element, xc, rel, family, profile, fmt, common, variants = ARMS[engine]
    folder = output / engine
    folder.mkdir()
    trials = []
    engine_path = subprocess.run([str(ROOT / "pseudoforge"), "engines", "path", engine],
                                 check=True, timeout=30, capture_output=True, text=True, env=env)
    binary = Path(engine_path.stdout.strip()).resolve(strict=True)
    for name, *options in (("default",), *variants):
        project = folder / name
        command = [str(ROOT / "pseudoforge"), "generate", "--engine", engine, "-e", element,
                   "-x", xc, "-r", rel, "-t", family, "-p", profile, "--format", fmt,
                   "--source", "local", "--no-autofix", "-j", "1", *common, *options, "-o", str(project)]
        item = {"id": name, "command": command, "options": options, "status": "failed"}
        started = time.monotonic()
        try:
            design.execute(command, folder, folder / f"{name}.log", env, timeout)
            delivered = json.loads((project / "reports/summary.json").read_text())["elements"][0]
            file = project / "pseudos" / delivered["pseudopotential"]
            if delivered["status"] not in ("ok", "ok-warn") or not file.is_file():
                raise ValueError("generation did not deliver a valid artifact")
            item.update(status=delivered["status"], output=str(file.relative_to(output)),
                        sha256=design.digest(file), native_summary=delivered)
            diagnostics = project / "tests/transferability.tsv"
            if diagnostics.is_file():
                item["native_transferability_tsv"] = diagnostics.read_text().splitlines()
        except (ValueError, OSError, KeyError, IndexError) as error:
            item["error"] = str(error)
            summary = project / "reports/summary.json"
            try:
                item["native_summary"] = json.loads(summary.read_text())["elements"][0]
            except (ValueError, OSError, KeyError, IndexError):
                pass
        item["elapsed_seconds"] = time.monotonic() - started
        trials.append(item)
        if "output" in item:
            try:
                item.update(native_diagnostics(engine, project, element))
            except (ValueError, OSError) as error:
                item["diagnostics_error"] = str(error)
        print(engine, name, item["status"], flush=True)
    return {"engine": engine, "element": element, "xc": xc, "relativity": rel,
            "profile": profile, "family": family, "format": fmt,
            "binary": str(binary), "binary_sha256": design.digest(binary), "trials": trials}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--engine", action="append", choices=ARMS)
    args = parser.parse_args()
    if args.jobs < 1 or args.timeout < 1:
        parser.error("jobs and timeout must be positive")
    output = args.output.resolve()
    output.mkdir()
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1")
    env.setdefault("OMPI_MCA_btl", "^uct")
    report = {"schema_version": 1, "scope": "native generation and engine-specific diagnostics",
              "git_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "concurrent_arms": args.jobs, "arms": []}
    engines = list(dict.fromkeys(args.engine or ARMS))
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        pending = {pool.submit(run_arm, output, engine, args.timeout, env): engine for engine in engines}
        arms = {}
        for job in as_completed(pending):
            engine = pending[job]
            try:
                arm = job.result()
            except (OSError, subprocess.SubprocessError) as error:
                arm = {"engine": engine, "error": str(error), "trials": []}
            arms[engine] = arm
            report["arms"] = [arms[key] for key in engines if key in arms]
            design.write_json(output / "report.json", report)
    return 0 if all(arm["trials"] and any(trial["status"] in ("ok", "ok-warn") for trial in arm["trials"])
                    for arm in report["arms"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
