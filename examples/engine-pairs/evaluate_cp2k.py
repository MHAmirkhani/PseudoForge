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
    return design.finite(float(energies[-1].lower().replace("d", "e")), "CP2K energy") * 2


def diamond_length(case):
    text = Path(case["input"]).read_text()
    length = re.search(r"\bcelldm\(1\)\s*=\s*(" + design.NUMBER + ")", text, re.I)
    if (case["composition"] != ("Si", "Si") or not length or not re.search(r"\bibrav\s*=\s*2\b", text, re.I) or
            set(case["tolerances"]) != {"relative_energy_Ry_atom"}):
        raise ValueError(f"{case['id']}: expected a two-Si cubic diamond EOS template and relative-energy tolerance")
    positions = re.search(r"^\s*ATOMIC_POSITIONS\s+alat\s*\n\s*Si\s+(.*?)\n\s*Si\s+(.*?)\n\s*K_POINTS\b", text, re.M)
    if not positions or [tuple(map(float, row.split())) for row in positions.groups()] != [(0., 0., 0.), (.25, .25, .25)]:
        raise ValueError(f"{case['id']}: Si positions differ from the diamond cell rendered for CP2K")
    return design.finite(float(length[1].lower().replace("d", "e")), "lattice parameter", positive=True) * BOHR_ANGSTROM


def reference_assessment(levels, cases, fraction):
    if len(levels) < 2:
        raise ValueError("verification requires a numerical ladder")
    entries = []
    by_id = {case["id"]: case for case in cases}
    for level in levels:
        energies = level["energy_Ry"]
        observations = []
        for case in cases:
            name = case["id"]
            errors = design.measure_errors(case, energies[name], energies, by_id)
            observations.append({"id": name, "errors": errors, "tolerances": case["tolerances"],
                                 "measurements": [energies[name]]})
        worst = max(item["errors"]["relative_energy_Ry_atom"] / item["tolerances"]["relative_energy_Ry_atom"]
                    for item in observations)
        entries.append({"cases": observations, "worst_normalized_error": worst, "passes": worst <= 1,
                        "cost_seconds": sum(level["wall_seconds"].values())})
    drift = [{"from_previous": design.numerical_drift(cases, previous, current, fraction),
              "from_base": design.numerical_drift(cases, entries[0], current, fraction)}
             for previous, current in zip(entries, entries[1:])]
    numerical_passes = all(row["from_previous"]["passes"] and row["from_base"]["passes"] for row in drift)
    return {**entries[-1], "passes": numerical_passes and all(e["passes"] for e in entries),
            "convergence": {"passes": numerical_passes, "drift_fraction": fraction, "levels": drift},
            "reference_passes": all(e["passes"] for e in entries)}


def evaluate(artifact, native, output, solver, env, cases, levels, *, folder_name=None):
    folder = output / (folder_name or artifact["id"])
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
            alat = diamond_length(case)
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
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--smoke", action="store_true", help="run the coarsest settings for consumer acceptance")
    mode.add_argument("--select", action="store_true", help="lock one feasible training candidate for held-out validation")
    ap.add_argument("-o", "--output", required=True, type=Path)
    args = ap.parse_args()
    solver = shutil.which(args.cp2k)
    if not solver:
        ap.error("CP2K executable not found")
    solver = str(Path(solver).resolve())
    original = args.si_protocol.read_bytes()
    protocol = design.load_protocol(args.si_protocol)
    if args.si_protocol.read_bytes() != original:
        raise ValueError("the protocol changed during validation")
    if (protocol["element"], protocol["xc"], protocol["relativity"]) != ("Si", "pbe", "scalar"):
        ap.error("use the scalar-PBE Si EOS example")
    catalog = json.loads(args.native_report.read_text())
    arm = next((row for row in catalog["arms"] if
                (row["engine"], row["element"], row["xc"], row["relativity"], row["format"]) ==
                ("gth", "Si", "pbe", "scalar", "gth")), None)
    if arm is None:
        ap.error("the native report has no completed GTH arm")
    for case in protocol["benchmarks"]:
        diamond_length(case)
    if args.select and "convergence" not in protocol:
        ap.error("--select needs a protocol with a declared convergence tolerance_fraction")
    args.output.mkdir()
    shutil.copyfile(args.basis, args.output / "BASIS")
    archive = args.output / "protocol-inputs"
    hashes = design.archive_protocol(protocol, original, archive)
    protocol = design.load_protocol(archive / "protocol.json")
    levels = LEVELS[:1] if args.smoke else LEVELS
    kinds = sorted({case["reference"]["kind"] for case in protocol["benchmarks"]})
    report = {"schema_version": 1, "scope": "CP2K GTH consumer smoke test" if args.smoke else "CP2K GTH EOS numerical ladder",
              "verification_scope": "two-atom scalar-PBE silicon diamond with the declared Gaussian basis and grid ladder",
              "solver_sha256": design.digest(solver), "basis_sha256": design.digest(args.output / "BASIS"), "results": [],
              "protocol_sha256": hashes["original.json"], "reference_kinds": kinds,
              "input_sha256": {case["id"]: case["input_sha256"] for case in protocol["benchmarks"]},
              "selected": None, "test": None, "meets_reference_constraints": False}
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1")
    env.setdefault("OMPI_MCA_btl", "^uct")
    with ThreadPoolExecutor(max_workers=3) as pool:
        jobs = []
        training = [case for case in protocol["benchmarks"] if case["split"] == "train"]
        fraction = protocol.get("convergence", {}).get("tolerance_fraction")
        artifacts = {row["id"]: row for row in arm["trials"] if "output" in row}
        for row in artifacts.values():
            jobs.append((row["id"], pool.submit(evaluate, row, args.native_report.parent,
                                               args.output, solver, env, training, levels)))
        for name, job in jobs:
            try:
                result = job.result()
                result["status"] = "evaluated"
                if fraction is not None and len(levels) > 1:
                    result["training"] = reference_assessment(result["levels"], training, fraction)
            except (OSError, ValueError) as error:
                result = {"id": name, "status": "failed", "error": str(error)}
            report["results"].append(result)
            design.write_json(args.output / "report.json", report)
    if args.select:
        feasible = [r for r in report["results"] if r.get("training", {}).get("passes")]
        winner = min(feasible, key=lambda r: (r["training"]["worst_normalized_error"], r["id"]), default=None)
        if winner:
            report["selected"] = winner["id"]
            report["selection_uses"] = "train only"
            design.write_json(args.output / "report.json", report)
            testing = [case for case in protocol["benchmarks"] if case["split"] == "test"]
            try:
                result = evaluate(artifacts[winner["id"]], args.native_report.parent, args.output,
                                  solver, env, testing, levels, folder_name="heldout-" + winner["id"])
                report["test"] = reference_assessment(result["levels"], testing, fraction)
                report["heldout_levels"] = result["levels"]
                report["meets_reference_constraints"] = report["test"]["passes"] and "synthetic-test" not in kinds
            except (ValueError, OSError) as error:
                report["test"] = {"passes": False, "error": str(error)}
        design.write_json(args.output / "report.json", report)
        return 0 if report["meets_reference_constraints"] else 2
    return 0 if report["results"] and all("error" not in row for row in report["results"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
