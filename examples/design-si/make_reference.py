#!/usr/bin/env python3
"""Produce an explicit QE/ONCV reference for an execution demonstration.

This is a cutoff-checked pseudopotential comparison on a small k mesh, not
an all-electron benchmark or evidence of improved physical accuracy.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("design", ROOT / "tools/pf_design.py")
design = importlib.util.module_from_spec(spec)
spec.loader.exec_module(design)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pw", required=True)
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise ValueError("choose a new or empty output directory")
    binary = shutil.which(args.pw)
    if not binary:
        raise ValueError("pw.x not found")
    pseudos = output / "pseudos"
    pseudos.mkdir(parents=True)
    upf = ROOT / "tests/fixtures/upf/Si.pbe-oncv.UPF"
    shutil.copyfile(upf, pseudos / "Si.UPF")
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1")
    env.setdefault("OMPI_MCA_btl", "^uct")
    cases = []
    source = {"description": "Si ONCV fixture, cutoff check at 80/100 Ry, rho=4*wfc; 2x2x2 k mesh",
              "pseudo_sha256": design.digest(upf), "solver_sha256": design.digest(binary), "solver": binary}
    for split in ("train", "test"):
        text = Path(__file__).with_name(split + ".in").read_text()
        (output / (split + ".in")).write_text(text)
        measurements = []
        for cutoff in (80, 100):
            folder = output / f"reference-{split}-{cutoff}"
            folder.mkdir()
            scratch = folder / "scratch"
            scratch.mkdir()
            rendered = text
            for key, value in {"PREFIX": "si_reference", "OUTDIR": str(scratch), "PSEUDO_DIR": str(pseudos),
                               "UPF": "Si.UPF", "ECUTWFC": str(cutoff), "ECUTRHO": str(4 * cutoff)}.items():
                rendered = rendered.replace("{{" + key + "}}", value)
            (folder / "input.in").write_text(rendered)
            design.execute([binary], folder, folder / "output.out", env, 300, rendered.encode())
            measurements.append(design.parse_qe((folder / "output.out").read_text(), 2))
        diffs = {}
        for key, rows, limit in (("forces_Ry_bohr", 2, 0.00025), ("stress_kbar", 3, 1.25)):
            diffs[key] = max(abs(a - b) for a, b in zip(design.vector(measurements[0][key], key, rows), design.vector(measurements[1][key], key, rows)))
            if diffs[key] > limit:
                raise ValueError(f"reference cutoff check failed for {split}/{key}: {diffs[key]}")
        source[split + "_cutoff_change"] = diffs
        cases.append({"id": split, "split": split, "input": split + ".in",
                      "reference": {"source": "reference.json and reference-" + split + "-100/output.out", "kind": "converged-pseudopotential",
                                    "xc": "pbe", "relativity": "scalar", **measurements[-1]},
                      "tolerances": {"force_max_Ry_bohr": 0.001, "stress_max_kbar": 5.0}})
    protocol = {"schema_version": 1, "element": "Si", "xc": "pbe", "relativity": "scalar", "repeats": 2,
                "reference_description": source["description"], "benchmarks": cases,
                "candidates": [
                    {"id": "paw", "engine": "ld1", "family": "paw", "profile": "psl-high", "options": {}, "grid": {"rcut_scale": [1.0, 1.1]}, "ecutwfc": 40, "ecutrho": 320},
                    {"id": "oncv", "engine": "oncvpsp", "family": "nc", "profile": "sg15", "options": {}, "grid": {"rcut_scale": [1.0, 1.1]}, "ecutwfc": 40, "ecutrho": 160},
                    {"id": "atompaw", "engine": "atompaw", "family": "paw", "profile": "atompaw", "options": {}, "ecutwfc": 40, "ecutrho": 320},
                ]}
    design.write_json(output / "reference.json", source)
    design.write_json(output / "protocol.json", protocol)
    print(output / "protocol.json")


if __name__ == "__main__":
    main()
