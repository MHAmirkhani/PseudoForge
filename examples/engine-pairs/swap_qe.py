#!/usr/bin/env python3
"""Measure a prespecified 2×2 Ti/O swap experiment on the oxide EOS pilot."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import pf_design as design

RY_TO_MEV = 13605.693122994


def signed_deltas(assessment, cases):
    measured = {case["id"]: case["measurements"][0]["energy_Ry"] for case in assessment["cases"]}
    by_id = {case["id"]: case for case in cases}
    return {case["group"]: (measured[case["id"]] - measured[case["relative_to"]]) * RY_TO_MEV / len(case["composition"])
            for case in by_id.values() if case["id"].endswith("-compressed")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("protocol", type=Path, help="grouped Ti EOS protocol")
    for option in ("ti-default", "ti-tuned", "o-default", "o-tuned"):
        parser.add_argument("--" + option, required=True, type=Path)
    parser.add_argument("--pw", required=True)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()
    pw = shutil.which(args.pw)
    if not pw or not 1 <= args.jobs <= 4:
        parser.error("provide pw.x and 1..4 jobs")
    protocol = design.load_protocol(args.protocol)
    if (protocol["element"], protocol["xc"], protocol["relativity"]) != ("Ti", "pbe", "scalar"):
        parser.error("use the grouped scalar-PBE Ti pilot protocol")
    cases = [case for case in protocol["benchmarks"] if case["split"] == "test"]
    if {case.get("group") for case in cases} != {"rocksalt", "fluorite"}:
        parser.error("provide grouped rocksalt and fluorite benchmarks")
    settings = protocol["candidates"][0]
    args.output.mkdir()
    # This is an intervention experiment on already examined materials,
    # separate from the original holdout. It does not reselect a winner.
    report = {"scope": "exploratory factorial intervention on previously examined oxides",
              "input_sha256": {case["id"]: case["input_sha256"] for case in cases},
              "solver_sha256": design.digest(pw), "results": {}}
    design.write_json(args.output / "report.json", report)
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1")
    env.setdefault("OMPI_MCA_btl", "^uct")
    def run(name, ti, o):
        directory = args.output / name
        pseudos = directory / "pseudos"
        pseudos.mkdir(parents=True)
        shutil.copyfile(ti, pseudos / "Ti.UPF")
        shutil.copyfile(o, pseudos / "O.fixed.UPF")
        row = {"ti_sha256": design.digest(pseudos / "Ti.UPF"), "o_sha256": design.digest(pseudos / "O.fixed.UPF")}
        try:
            assessment = design.evaluate(protocol, settings, directory, cases, pw, env)
            row["evaluation"] = assessment
            if assessment["convergence"]["passes"]:
                row["tight_signed_energy_deltas_meV_atom"] = signed_deltas(
                    assessment["convergence"]["levels"][-1]["assessment"], cases)
        except (ValueError, OSError) as error:
            row["error"] = str(error)
        return name, row

    jobs = [(f"ti-{ti_key}_o-{o_key}", ti, o)
            for ti_key, ti in (("baseline", args.ti_default), ("tuned", args.ti_tuned))
            for o_key, o in (("baseline", args.o_default), ("tuned", args.o_tuned))]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for job in as_completed([pool.submit(run, *args) for args in jobs]):
            name, row = job.result()
            report["results"][name] = row
            design.write_json(args.output / "report.json", report)
    energy = [report["results"][name].get("tight_signed_energy_deltas_meV_atom") for name, _, _ in jobs]
    if all(energy):
        base, oxygen, titanium, both = energy
        report["interaction_meV_atom"] = {group: both[group] - oxygen[group] - titanium[group] + base[group]
                                         for group in base}
        design.write_json(args.output / "report.json", report)


if __name__ == "__main__":
    main()
