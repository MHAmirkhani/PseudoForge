#!/usr/bin/env python3
"""Measure the GTH silicon pairs with CP2K and a matched numerical ladder."""
import argparse
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import pf_design as design

LEVELS = (
    ("DZVP", 400, 60, 2),
    ("DZVP", 600, 60, 2),
    ("DZVP", 600, 90, 2),
    ("TZV2P", 600, 90, 2),
    ("TZV2P", 600, 90, 3),
)
BOHR_ANGSTROM = 0.529177210903
RY_TO_MEV = 13605.693122994


def input_text(length, settings):
    basis, cutoff, relcut, mesh = settings
    half, quarter = length / 2, length / 4
    return f"""&GLOBAL
  PROJECT silicon
  RUN_TYPE ENERGY
  PRINT_LEVEL LOW
&END GLOBAL
&FORCE_EVAL
  METHOD Quickstep
  &DFT
    BASIS_SET_FILE_NAME ../../BASIS
    POTENTIAL_FILE_NAME ../potential.gth
    &QS
      EPS_DEFAULT 1.0E-12
    &END QS
    &MGRID
      CUTOFF {cutoff}
      REL_CUTOFF {relcut}
    &END MGRID
    &SCF
      EPS_SCF 1.0E-8
      MAX_SCF 80
    &END SCF
    &XC
      &XC_FUNCTIONAL PBE
      &END XC_FUNCTIONAL
    &END XC
    &KPOINTS
      SCHEME MONKHORST-PACK {mesh} {mesh} {mesh}
    &END KPOINTS
  &END DFT
  &SUBSYS
    &CELL
      A 0 {half:.12f} {half:.12f}
      B {half:.12f} 0 {half:.12f}
      C {half:.12f} {half:.12f} 0
    &END CELL
    &COORD
      Si 0 0 0
      Si {quarter:.12f} {quarter:.12f} {quarter:.12f}
    &END COORD
    &KIND Si
      BASIS_SET {basis}-MOLOPT-PBE-GTH-q4
      POTENTIAL GTH-PBE-PSEUDOFORGE
    &END KIND
  &END SUBSYS
&END FORCE_EVAL
"""


def parse_energy(text):
    if "PROGRAM ENDED AT" not in text or "SCF run converged" not in text:
        raise ValueError("CP2K did not finish a converged SCF calculation")
    energies = re.findall(r"^\s*ENERGY\|.*?(" + design.NUMBER + r")\s*$", text, re.M)
    if not energies:
        raise ValueError("CP2K log has no total energy")
    return design.finite(float(energies[-1].replace("D", "e")), "CP2K energy") * 2


def evaluate(artifact, native, output, solver, env, cases, levels):
    folder = output / artifact["id"]
    folder.mkdir()
    potential = folder / "potential.gth"
    shutil.copyfile(native / artifact["output"], potential)
    if design.digest(potential) != artifact["sha256"]:
        raise ValueError("native potential digest changed")
    result = {"id": artifact["id"], "sha256": artifact["sha256"], "levels": []}
    for index, settings in enumerate(levels):
        energies = {}
        timings = {}
        for case in cases:
            path = folder / f"level{index}-{case['id']}"
            path.mkdir()
            text = Path(case["input"]).read_text()
            alat = float(re.search(r"celldm\(1\)=(" + design.NUMBER + ")", text)[1]) * BOHR_ANGSTROM
            (path / "input.inp").write_text(input_text(alat, settings))
            timings[case["id"]] = design.execute([solver, "-i", "input.inp", "-o", "output.out"],
                                                  path, path / "launcher.log", env, 600)
            energies[case["id"]] = {"energy_Ry": parse_energy((path / "output.out").read_text())}
        by_id = {case["id"]: case for case in cases}
        errors = defaultdict(dict)
        signed = defaultdict(dict)
        for case in cases:
            name = case["id"]
            error = design.measure_errors(case, energies[name], energies, by_id)["relative_energy_Ry_atom"]
            errors[case["split"]][name] = error * RY_TO_MEV
            delta = energies[name]["energy_Ry"] - energies[case["relative_to"]]["energy_Ry"]
            signed[case["split"]][name] = delta * RY_TO_MEV / len(case["composition"])
        result["levels"].append({"basis": settings[0], "cutoff_Ry": settings[1], "rel_cutoff_Ry": settings[2],
                                 "k_mesh": settings[3], "errors_meV_atom": errors,
                                 "signed_meV_atom": signed, "energy_Ry": energies, "wall_seconds": timings})
        design.write_json(folder / "report.json", result)
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("native_report", type=Path)
    ap.add_argument("si_protocol", type=Path)
    ap.add_argument("--cp2k", required=True)
    ap.add_argument("--basis", required=True, type=Path, help="CP2K BASIS_MOLOPT_UZH")
    ap.add_argument("--smoke", action="store_true", help="run the coarsest settings for consumer acceptance")
    ap.add_argument("-o", "--output", required=True, type=Path)
    args = ap.parse_args()
    solver = shutil.which(args.cp2k)
    if not solver:
        ap.error("CP2K executable not found")
    protocol = design.load_protocol(args.si_protocol)
    if (protocol["element"], protocol["xc"], protocol["relativity"]) != ("Si", "pbe", "scalar"):
        ap.error("use the scalar-PBE Si EOS example")
    catalog = json.loads(args.native_report.read_text())
    arm = next((row for row in catalog["arms"] if row["engine"] == "gth"), None)
    if arm is None:
        ap.error("the native report has no completed GTH arm")
    args.output.mkdir()
    shutil.copyfile(args.basis, args.output / "BASIS")
    levels = LEVELS[:1] if args.smoke else LEVELS
    report = {"scope": "CP2K GTH consumer smoke test" if args.smoke else "CP2K GTH EOS numerical ladder",
              "solver_sha256": design.digest(solver), "basis_sha256": design.digest(args.basis), "results": []}
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1")
    env.setdefault("OMPI_MCA_btl", "^uct")
    with ThreadPoolExecutor(max_workers=3) as pool:
        jobs = []
        # Evaluate the training volumes to distinguish consumer acceptance
        # from a transferable improvement. This script selects no candidate.
        training = [case for case in protocol["benchmarks"] if case["split"] == "train"]
        for row in arm["trials"]:
            if "output" in row:
                jobs.append((row["id"], pool.submit(evaluate, row, args.native_report.parent,
                                                   args.output, solver, env, training, levels)))
        for name, job in jobs:
            try:
                result = job.result()
            except (OSError, ValueError) as error:
                result = {"id": name, "error": str(error)}
            report["results"].append(result)
            design.write_json(args.output / "report.json", report)
    return 0 if report["results"] and all("error" not in row for row in report["results"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
