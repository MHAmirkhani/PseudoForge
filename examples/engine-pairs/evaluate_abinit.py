#!/usr/bin/env python3
"""Check the fhi98PP Si/PW panel with ABINIT's format-6 reader."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import pf_design as design

LENGTHS_BOHR = (10.1, 10.4)
SETTINGS = ((30, 4), (45, 4), (45, 6), (45, 8), (45, 10))
HARTREE_TO_MEV = 27211.386245988


def format6(source):
    # ABINIT format 6 reads the original semilocal CPI radial records after
    # seven extra lines. This panel is Si/PW92 with no nonlinear core charge.
    data = source.read_bytes()
    lines = data.splitlines()
    valence, channels = lines[0].split()
    count = int(channels)
    mesh = int(lines[11].split()[0])
    if float(valence) != 4 or not 1 <= count <= 5 or mesh < 2 or len(lines) != 11 + count * (1 + mesh):
        raise ValueError("expected four-electron Si CPI with a common grid and no core-charge tail")
    if any(int(lines[11 + i * (1 + mesh)].split()[0]) != mesh for i in range(count)):
        raise ValueError("CPI radial grids differ in size")
    lmax = count - 1
    header = (
        "PseudoForge fhi98PP Si, PW92, highest channel local\n"
        "14 4 0\n"
        f"6 7 {lmax} {lmax} {mesh} 0\n"
        "0.0 0.0 0.0\n"
        "\n"
        "\n"
        "CPI radial records follow\n"
    )
    return header.encode("ascii") + data


def input_text(length, cutoff, mesh):
    return f"""pseudos "Si.fhi"
ixc 7
acell 3*{length} bohr
rprim 0 .5 .5
      .5 0 .5
      .5 .5 0
natom 2
ntypat 1
znucl 14
typat 2*1
xred 0 0 0
     .25 .25 .25
ecut {cutoff}
ngkpt 3*{mesh}
nshiftk 1
shiftk 0 0 0
tolvrs 1.0d-12
nstep 80
prtden 0
prtwf 0
"""


def evaluate(native, trial, output, solver, env):
    source = native / trial["output"]
    if design.digest(source) != trial["sha256"]:
        raise ValueError(f"{source}: CPI checksum differs from the native report")
    converted = format6(source)
    result = {"id": trial["id"], "cpi_sha256": trial["sha256"], "levels": []}
    for cutoff, mesh in SETTINGS:
        energies, times = [], []
        for index, length in enumerate(LENGTHS_BOHR, start=1):
            case = output / trial["id"] / f"ecut{cutoff}-k{mesh}" / f"volume{index}"
            case.mkdir(parents=True)
            pseudo = case / "Si.fhi"
            pseudo.write_bytes(converted)
            result["psp6_sha256"] = design.digest(pseudo)
            (case / "si.abi").write_text(input_text(length, cutoff, mesh))
            times.append(design.execute([solver, "si.abi"], case, case / "stdout.log", env, 240))
            log = (case / "si.abo").read_text(errors="replace")
            final = re.findall(r"^\s*etotal\s+(" + design.NUMBER + r")", log, re.M)
            if not re.search(r"At SCF step[^\n]*=>converged\.", log) or "Calculation completed." not in log or not final:
                raise ValueError(f"ABINIT did not report SCF convergence and a final energy in {case}")
            energy = float(final[-1].lower().replace("d", "e"))
            if not math.isfinite(energy):
                raise ValueError(f"nonfinite final energy in {case}")
            energies.append(energy)
        result["levels"].append({"ecut_Ha": cutoff, "k_mesh": mesh, "energy_Ha": energies,
                                 "delta_meV_atom": (energies[1] - energies[0]) * HARTREE_TO_MEV / 2,
                                 "wall_seconds": times})
        design.write_json(output / trial["id"] / "report.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native_report", type=Path)
    parser.add_argument("--abinit", required=True)
    parser.add_argument("-o", "--output", required=True, type=Path)
    args = parser.parse_args()
    solver = shutil.which(args.abinit)
    if not solver:
        parser.error("supply an installed ABINIT executable")
    solver = str(Path(solver).resolve())
    native = json.loads(args.native_report.read_text())
    arms = [arm for arm in native["arms"] if
            (arm["engine"], arm["element"], arm["xc"], arm["relativity"], arm["format"]) ==
            ("fhi98pp", "Si", "pw", "scalar", "cpi")]
    if len(arms) != 1:
        parser.error("need one matched scalar Si/PW fhi98PP CPI arm")
    args.output.mkdir(parents=True)
    report = {"scope": "two-volume native-consumer comparison without an all-electron reference",
              "solver_sha256": design.digest(solver), "lengths_bohr": LENGTHS_BOHR, "trials": []}
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1")
    env.setdefault("OMPI_MCA_btl", "^uct")
    for trial in arms[0]["trials"]:
        try:
            if not trial.get("output"):
                raise ValueError("native generation gave no deliverable")
            result = evaluate(args.native_report.parent, trial, args.output, solver, env)
        except (ValueError, OSError, IndexError) as error:
            result = {"id": trial["id"], "error": str(error)}
        report["trials"].append(result)
        design.write_json(args.output / "report.json", report)
    return 2 if any("error" in trial for trial in report["trials"]) else 0


if __name__ == "__main__":
    sys.exit(main())
