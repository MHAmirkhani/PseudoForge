#!/usr/bin/env python3
"""Check the ADPACK He panel with the OpenMX VPS reader and an isolated atom."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import math
import os
from pathlib import Path
import re
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import pf_design as design

SETTINGS = (("He8.0", 220), ("He8.0", 300), ("He10.0", 300))


def input_text(basis, cutoff):
    return f"""System.CurrrentDir ./
System.Name He
DATA.PATH ./data
level.of.stdout 2
level.of.fileout 0
Species.Number 1
<Definition.of.Atomic.Species
 He {basis}-s2p1 HeTrial
Definition.of.Atomic.Species>
Atoms.Number 1
Atoms.SpeciesAndCoordinates.Unit Ang
<Atoms.SpeciesAndCoordinates
 1 He 0.0 0.0 0.0 1.0 1.0
Atoms.SpeciesAndCoordinates>
scf.XcType LDA
scf.SpinPolarization off
scf.EigenvalueSolver Cluster
scf.energycutoff {cutoff}
scf.maxIter 80
scf.criterion 1e-7
scf.Mixing.Type gr-pulay
scf.Init.Mixing.Weight 0.15
scf.Min.Mixing.Weight 0.02
scf.Max.Mixing.Weight 0.4
scf.Mixing.StartPulay 6
"""


def evaluate(trial, source_dir, output, solver, bases, env):
    vps = source_dir / trial["output"]
    if design.digest(vps) != trial["sha256"]:
        raise ValueError("VPS checksum differs from the native report")
    result = {"id": trial["id"], "vps_sha256": trial["sha256"], "levels": []}
    for basis, cutoff in SETTINGS:
        case = output / trial["id"] / f"{basis}-{cutoff}"
        pao = case / "data/PAO"
        pao.mkdir(parents=True)
        target = case / "data/VPS"
        target.mkdir()
        shutil.copyfile(vps, target / "HeTrial.vps")
        shutil.copyfile(bases[basis], pao / bases[basis].name)
        (case / "He.dat").write_text(input_text(basis, cutoff))
        logfile = case / "stdout.log"
        seconds = design.execute([solver, "He.dat", "-nt", "1"], case, logfile, env, 180)
        log = logfile.read_text(errors="replace")
        total = re.findall(r"^\s*Utot\s*=\s*(" + design.NUMBER + r")", log, re.M)
        if "The SCF was achieved at MD=" not in log or "calculation was normally finished." not in log or not total:
            raise ValueError(f"OpenMX did not report SCF convergence and a final energy in {case}")
        energy = float(total[-1].lower().replace("d", "e"))
        if not math.isfinite(energy):
            raise ValueError(f"nonfinite final energy in {case}")
        result["levels"].append({"basis": basis, "integration_cutoff_Ry": cutoff,
                                 "energy_Ha": energy, "wall_seconds": seconds})
        design.write_json(output / trial["id"] / "report.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native_report", type=Path)
    parser.add_argument("--openmx", required=True)
    parser.add_argument("--pao-dir", type=Path, required=True, help="OpenMX DFT_DATA19/PAO")
    parser.add_argument("-o", "--output", required=True, type=Path)
    args = parser.parse_args()
    executable = shutil.which(args.openmx)
    if not executable:
        parser.error("supply an installed OpenMX executable")
    solver = str(Path(executable).resolve())
    bases = {basis: args.pao_dir / f"{basis}.pao" for basis, _ in SETTINGS}
    if any(not path.is_file() for path in bases.values()):
        parser.error("PAO directory needs the He8.0 and He10.0 bases")
    native = json.loads(args.native_report.read_text())
    arms = [arm for arm in native["arms"] if
            (arm["engine"], arm["element"], arm["xc"], arm["relativity"], arm["format"]) ==
            ("adpack", "He", "pz", "full", "openmx")]
    if len(arms) != 1:
        parser.error("need one matched fully relativistic He/PZ ADPACK VPS arm")
    args.output.mkdir(parents=True)
    report = {"scope": "isolated-He native-consumer and numerical smoke test without a reference",
              "solver_sha256": design.digest(solver),
              "basis_sha256": {basis: design.digest(path) for basis, path in bases.items()},
              "trials": []}
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1")
    env.setdefault("OMPI_MCA_btl", "^uct")
    with ThreadPoolExecutor(max_workers=3) as pool:
        runs = [(trial, pool.submit(evaluate, trial, args.native_report.parent, args.output, solver, bases, env))
                for trial in arms[0]["trials"] if trial.get("output")]
        for trial, future in runs:
            try:
                result = future.result()
            except (ValueError, OSError) as error:
                result = {"id": trial["id"], "error": str(error)}
            report["trials"].append(result)
        report["trials"].extend({"id": trial["id"], "error": "native generation gave no deliverable"}
                                for trial in arms[0]["trials"] if not trial.get("output"))
    design.write_json(args.output / "report.json", report)
    return 2 if any("error" in trial for trial in report["trials"]) else 0


if __name__ == "__main__":
    sys.exit(main())
